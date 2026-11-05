import AppKit
import Foundation
import MagicTapCore

/// Finds the Magic Mouse among the multitouch devices and streams its frames.
final class MouseMonitor {
    typealias FrameHandler = (_ touches: [TouchPoint], _ timestamp: TimeInterval) -> Void

    /// The C callback has no context pointer, so the handler is global.
    /// Frames are always forwarded to the main queue.
    fileprivate static var frameHandler: FrameHandler?

    private let api: MultitouchAPI
    private let verbose: Bool
    private var deviceList: CFArray?
    private var active: [MTDevice] = []
    /// Stable hardware IDs of the active mice. Device pointers are NOT stable:
    /// MTDeviceCreateList returns fresh objects on every call, so comparing
    /// them would restart the mouse on every rescan.
    private var signature: [UInt64] = []
    private var rescanTimer: Timer?

    init(api: MultitouchAPI, verbose: Bool = false) {
        self.api = api
        self.verbose = verbose
    }

    func start(onFrame: @escaping FrameHandler) {
        Self.frameHandler = onFrame
        rescan(force: true)
        // Bluetooth devices come and go; re-check periodically and on wake.
        rescanTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.rescan(force: false)
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.rescan(force: true) }
    }

    func stop() {
        rescanTimer?.invalidate()
        rescanTimer = nil
        stopDevices()
        Self.frameHandler = nil
    }

    /// Human-readable list of the devices that are being listened to.
    var activeDeviceCount: Int { active.count }

    private func rescan(force: Bool) {
        guard let list = api.createList()?.takeRetainedValue() else { return }
        let devices = (list as [AnyObject]).map { Unmanaged.passUnretained($0).toOpaque() }
        let mice = devices.filter(isMagicMouse)
        let newSignature = mice.map(hardwareID).sorted()
        guard force || newSignature != signature else { return }

        stopDevices()
        deviceList = list // keep the device objects alive while in use
        signature = newSignature
        active = mice
        for device in mice {
            api.registerCallback(device, contactCallback)
            _ = api.start(device, 0)
        }
        if verbose { print("[monitor] listening to \(mice.count) Magic Mouse device(s)") }
    }

    private func stopDevices() {
        for device in active {
            api.unregisterCallback(device, contactCallback)
            _ = api.stop(device)
        }
        active = []
        signature = []
        deviceList = nil
    }

    private func hardwareID(_ device: MTDevice) -> UInt64 {
        var id: UInt64 = 0
        _ = api.deviceID(device, &id)
        return id
    }

    /// The Magic Mouse is an external multitouch surface that is taller than
    /// it is wide (≈ 52 × 90 mm). Built-in trackpads and Magic Trackpads are
    /// landscape, so they are excluded: they already have native tap-to-click.
    private func isMagicMouse(_ device: MTDevice) -> Bool {
        if api.isBuiltIn(device) { return false }
        var width: Int32 = 0
        var height: Int32 = 0
        guard api.surfaceDimensions(device, &width, &height) == 0 else { return false }
        return height > width
    }
}

private let contactCallback: MTContactCallback = { _, touches, count, timestamp, _ in
    var points: [TouchPoint] = []
    if let touches, count > 0 {
        for index in 0 ..< Int(count) {
            let record = UnsafeRawPointer(touches) + index * MTTouchLayout.stride
            let state = record.loadUnaligned(fromByteOffset: MTTouchLayout.stateOffset, as: Int32.self)
            guard MTTouchLayout.isTouching(state) else { continue }
            let x = record.loadUnaligned(fromByteOffset: MTTouchLayout.xOffset, as: Float.self)
            let y = record.loadUnaligned(fromByteOffset: MTTouchLayout.yOffset, as: Float.self)
            points.append(TouchPoint(x: x, y: y))
        }
    }
    DispatchQueue.main.async {
        MouseMonitor.frameHandler?(points, timestamp)
    }
}
