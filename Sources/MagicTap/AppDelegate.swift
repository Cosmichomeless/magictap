import AppKit
import MagicTapCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let detector = TapDetector(config: Settings.tapConfig)
    private var monitor: MouseMonitor?
    private var buttonMonitor: Any?
    private let debug: Bool

    init(debug: Bool) {
        self.debug = debug
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()

        guard let api = MultitouchAPI.load() else {
            showFatal("MultitouchSupport is not available on this version of macOS.")
            return
        }

        if !debug { ClickPoster.requestTrust() }

        // A physical click while fingers are down must not also produce a tap.
        buttonMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            guard Date() >= ClickPoster.ignoreButtonEventsUntil else { return }
            self?.detector.noteButtonEvent()
        }

        let monitor = MouseMonitor(api: api)
        self.monitor = monitor
        monitor.start { [weak self] touches, timestamp in
            self?.handleFrame(touches: touches, timestamp: timestamp)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        if let buttonMonitor { NSEvent.removeMonitor(buttonMonitor) }
    }

    // MARK: Input

    private func handleFrame(touches: [TouchPoint], timestamp: TimeInterval) {
        guard Settings.enabled else {
            detector.reset()
            return
        }
        if debug {
            let fingers = touches.map { String(format: "(%.2f, %.2f)", $0.x, $0.y) }.joined(separator: " ")
            print(String(format: "%.3f  fingers=%d  %@", timestamp, touches.count, fingers))
        }
        guard let action = detector.process(
            time: timestamp, touches: touches, cursor: ClickPoster.cursorLocation
        ) else { return }

        if debug {
            print("→ \(action)")
        } else if ClickPoster.isTrusted {
            ClickPoster.post(action)
        }
    }

    // MARK: Menu

    private func configureStatusItem() {
        let image = NSImage(systemSymbolName: "computermouse", accessibilityDescription: "MagicTap")
        image?.isTemplate = true
        statusItem.button?.image = image
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(item("Enabled", #selector(toggleEnabled), checked: Settings.enabled))
        menu.addItem(.separator())
        menu.addItem(item("Tap → left click", #selector(toggleLeft), checked: Settings.singleFingerLeftClick))
        menu.addItem(item("Two-finger tap → right click", #selector(toggleRight), checked: Settings.twoFingerRightClick))
        menu.addItem(.separator())

        let mouseCount = monitor?.activeDeviceCount ?? 0
        let mouseLine = mouseCount > 0 ? "Magic Mouse detected" : "No Magic Mouse found"
        menu.addItem(withTitle: mouseLine, action: nil, keyEquivalent: "").isEnabled = false

        if !ClickPoster.isTrusted {
            menu.addItem(item("Grant Accessibility permission…", #selector(openAccessibility)))
        }
        menu.addItem(item("Launch at login", #selector(toggleLaunchAtLogin), checked: SMAppService.mainApp.status == .enabled))
        menu.addItem(.separator())
        menu.addItem(item("Quit MagicTap", #selector(NSApplication.terminate(_:)), key: "q"))
    }

    private func item(_ title: String, _ action: Selector, checked: Bool = false, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = action == #selector(NSApplication.terminate(_:)) ? NSApp : self
        item.state = checked ? .on : .off
        return item
    }

    @objc private func toggleEnabled() {
        Settings.enabled.toggle()
        statusItem.button?.appearsDisabled = !Settings.enabled
        detector.reset()
    }

    @objc private func toggleLeft() {
        Settings.singleFingerLeftClick.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func toggleRight() {
        Settings.twoFingerRightClick.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func openAccessibility() {
        ClickPoster.requestTrust()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            // Only works from a bundled .app (scripts/build-app.sh), not `swift run`.
            let alert = NSAlert(error: error)
            alert.messageText = "Could not change launch at login"
            alert.runModal()
        }
    }

    private func showFatal(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "MagicTap cannot start"
        alert.informativeText = message
        alert.runModal()
        NSApp.terminate(nil)
    }
}
