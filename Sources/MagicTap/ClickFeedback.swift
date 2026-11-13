import AppKit
import Foundation
import MagicTapCore

/// Tapping has no physical feedback (the Magic Mouse has no haptic motor), so
/// the cursor "pulses": the *real* system cursor grows a little and settles
/// back. That needs the private WindowServer call `CGSSetCursorScale`, loaded
/// dynamically; if it is missing, a copy of the cursor drawn on top of the real
/// one is animated instead.
enum ClickFeedback {
    /// How much bigger the cursor gets at the peak of the pulse (a setting).
    private static var peakScale: CGFloat { CGFloat(Settings.pulseSize) }
    private static let duration: CFTimeInterval = 0.2

    /// Pulses and/or plays a sound for click-like actions; other actions do nothing.
    /// `location` is in CoreGraphics coordinates (origin top-left of the main display).
    static func show(for action: TapAction, at location: CGPoint, dragOrigin: CGPoint) {
        switch action {
        case .leftClick, .rightClick, .middleClick: feedback(at: location)
        case .doubleClick:
            feedback(at: location)
            feedback(at: location, delay: duration + 0.04)
        case .dragStart: feedback(at: dragOrigin)
        default: break
        }
    }

    private static func feedback(at location: CGPoint, delay: TimeInterval = 0) {
        if Settings.clickFeedback { pulse(at: location, delay: delay) }
        if Settings.clickSound { playSound(after: delay) }
    }

    private static let sound: NSSound? = {
        let file = "/System/Library/Sounds/Tink.aiff"
        return NSSound(contentsOfFile: file, byReference: true) ?? NSSound(named: "Tink")
    }()

    private static func playSound(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard let sound else { return }
            sound.stop() // restart if a previous click is still ringing
            sound.volume = Float(Settings.soundVolume)
            sound.play()
        }
    }

    /// Puts the real cursor back at its normal size (used on quit / when disabled).
    static func restoreCursor() {
        NativeCursorScale.shared?.cancel()
    }

    private static func pulse(at location: CGPoint, delay: TimeInterval = 0) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let native = NativeCursorScale.shared {
                native.pulse(peak: Float(peakScale), duration: duration)
            } else {
                overlayPulse(at: location)
            }
        }
    }

    private static func overlayPulse(at location: CGPoint) {
        let cursor = NSCursor.currentSystem ?? NSCursor.arrow
        let image = cursor.image
        let size = image.size
        guard size.width > 0, size.height > 0 else { return }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }

        // AppKit's origin is bottom-left; the hotspot is measured from the image's top-left.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let hotspot = cursor.hotSpot
        let tip = CGPoint(x: location.x, y: mainHeight - location.y)
        let margin = max(size.width, size.height) // room for the enlarged copy
        let panelSize = CGSize(width: size.width + margin * 2, height: size.height + margin * 2)
        // Tip position inside the panel (bottom-left origin).
        let tipInPanel = CGPoint(x: margin + hotspot.x, y: margin + size.height - hotspot.y)

        let panel = NSPanel(
            contentRect: NSRect(
                x: tip.x - tipInPanel.x, y: tip.y - tipInPanel.y,
                width: panelSize.width, height: panelSize.height
            ),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.isReleasedWhenClosed = false

        let view = NSView(frame: NSRect(origin: .zero, size: panelSize))
        view.wantsLayer = true
        let layer = CALayer()
        layer.contents = cgImage
        layer.contentsScale = scale
        layer.bounds = CGRect(origin: .zero, size: size)
        // Scale around the cursor's tip so it stays put while it grows.
        layer.anchorPoint = CGPoint(x: hotspot.x / size.width, y: 1 - hotspot.y / size.height)
        layer.position = tipInPanel
        view.layer?.addSublayer(layer)
        panel.contentView = view
        panel.orderFrontRegardless()

        let grow = CAKeyframeAnimation(keyPath: "transform.scale")
        grow.values = [1.0, peakScale, 1.0]
        grow.keyTimes = [0, 0.4, 1]
        grow.timingFunctions = [CAMediaTimingFunction(name: .easeOut), CAMediaTimingFunction(name: .easeInEaseOut)]
        grow.duration = duration
        CATransaction.begin()
        CATransaction.setCompletionBlock { panel.close() }
        layer.add(grow, forKey: "pulse")
        CATransaction.commit()
    }
}

/// Scales the real cursor through the private SkyLight/CoreGraphics functions.
/// `shared` is nil when they are not available on this system.
private final class NativeCursorScale {
    private typealias ConnectionFn = @convention(c) () -> Int32
    private typealias SetFn = @convention(c) (Int32, Float) -> Int32
    private typealias GetFn = @convention(c) (Int32, UnsafeMutablePointer<Float>) -> Int32

    static let shared = NativeCursorScale()

    private let connection: Int32
    private let setScale: SetFn
    private let getScale: GetFn
    private var baseScale: Float = 1
    private var timer: Timer?
    private var lastEnvelope = 0.0

    private init?() {
        let paths = [
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics",
        ]
        var found: (ConnectionFn, SetFn, GetFn)?
        for path in paths {
            guard let handle = dlopen(path, RTLD_NOW),
                  let c = dlsym(handle, "CGSMainConnectionID"),
                  let s = dlsym(handle, "CGSSetCursorScale"),
                  let g = dlsym(handle, "CGSGetCursorScale") else { continue }
            found = (unsafeBitCast(c, to: ConnectionFn.self),
                     unsafeBitCast(s, to: SetFn.self),
                     unsafeBitCast(g, to: GetFn.self))
            break
        }
        guard let (connectionID, set, get) = found else { return nil }
        let id = connectionID()
        var value: Float = 0
        guard get(id, &value) == 0, value > 0 else { return nil }
        connection = id
        setScale = set
        getScale = get
    }

    /// Grows the cursor to `peak` times its normal size and back over `duration`.
    /// A pulse that starts while another is running restarts the curve but keeps
    /// the original base size, so the user's own cursor size is never lost.
    func pulse(peak: Float, duration: TimeInterval) {
        if timer == nil {
            var current: Float = 0
            guard getScale(connection, &current) == 0, current > 0 else { return }
            baseScale = current
        }
        timer?.invalidate()
        // Overlapping pulse: resume the rising edge from where the cursor is now
        // instead of snapping back to its normal size.
        let resumed = timer == nil ? 0 : Self.riseProgress(for: lastEnvelope)
        let start = CACurrentMediaTime() - resumed * duration
        let base = baseScale
        let top = min(base * peak, 4)
        let t = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            let progress = (CACurrentMediaTime() - start) / duration
            if progress >= 1 {
                self.cancel()
                return
            }
            let value = Self.envelope(progress)
            self.lastEnvelope = value
            _ = self.setScale(self.connection, base + (top - base) * Float(value))
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    /// Stops any running pulse and puts the cursor back at its base size.
    func cancel() {
        guard timer != nil else { return }
        timer?.invalidate()
        timer = nil
        _ = setScale(connection, baseScale)
    }

    private static let rise = 0.35

    /// Progress (0…rise) at which the rising edge reaches `value`.
    private static func riseProgress(for value: Double) -> Double {
        asin(min(max(value, 0), 1)) / (.pi / 2) * rise
    }

    /// 0 → 1 → 0: a quick ease-out rise (35 % of the time) and a slower ease-in-out fall.
    private static func envelope(_ t: Double) -> Double {
        if t < rise { return sin(t / rise * .pi / 2) }
        return cos((t - rise) / (1 - rise) * .pi / 2)
    }
}
