import AppKit
import MagicTapCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let detector = TapDetector(config: Settings.tapConfig)
    private var monitor: MouseMonitor?
    private var buttonMonitor: Any?
    private let debug: Bool
    private var lastFrame = Date()
    private var dragWatchdog: Timer?
    private let settingsWindow = SettingsWindowController()
    private var windowVisible = false

    init(debug: Bool) {
        self.debug = debug
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        settingsWindow.onVisibilityChange = { [weak self] visible in
            self?.windowVisible = visible
            if !visible { LiveModel.shared.clear() }
        }
        LiveModel.shared.mouseCount = { [weak self] in self?.monitor?.activeDeviceCount ?? 0 }
        NotificationCenter.default.addObserver(
            forName: .magicTapSettingsChanged, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            self.detector.config = Settings.tapConfig
            self.statusItem.button?.appearsDisabled = !Settings.enabled
            if !Settings.enabled { self.releaseDrag() }
        }

        guard let api = MultitouchAPI.load() else {
            showFatal("MultitouchSupport is not available on this version of macOS.")
            return
        }

        // First run without the permission: walk the user through it.
        if !debug, !ClickPoster.isTrusted {
            ClickPoster.requestTrust()
            settingsWindow.show(tab: .setup)
        }

        // A physical click while fingers are down must not also produce a tap.
        buttonMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] _ in
            ClickPoster.missionControlOpen = false // any click leaves Mission Control
            guard Date() >= ClickPoster.ignoreButtonEventsUntil else { return }
            self?.detector.noteButtonEvent()
        }

        let monitor = MouseMonitor(api: api, verbose: debug)
        self.monitor = monitor
        monitor.start { [weak self] touches, timestamp in
            self?.handleFrame(touches: touches, timestamp: timestamp)
        }
        // If the mouse disappears mid-drag no "all fingers lifted" frame ever
        // arrives; never leave the button stuck down.
        dragWatchdog = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, self.detector.isDragging, Date().timeIntervalSince(self.lastFrame) > 1 else { return }
            self.releaseDrag()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        releaseDrag()
        monitor?.stop()
        if let buttonMonitor { NSEvent.removeMonitor(buttonMonitor) }
    }

    // MARK: Input

    private func handleFrame(touches: [TouchPoint], timestamp: TimeInterval) {
        lastFrame = Date()
        guard Settings.enabled else {
            releaseDrag()
            if windowVisible { LiveModel.shared.push(touches: touches, action: nil) }
            return
        }
        if debug {
            let fingers = touches.map { String(format: "(%.2f, %.2f)", $0.x, $0.y) }.joined(separator: " ")
            print(String(format: "%.3f  fingers=%d  %@", timestamp, touches.count, fingers))
        }
        let result = detector.process(
            time: timestamp, touches: touches, cursor: ClickPoster.cursorLocation
        )
        if windowVisible { LiveModel.shared.push(touches: touches, action: result) }
        guard let action = result else {
            if detector.isDragging, !debug, ClickPoster.isTrusted { ClickPoster.sendDragged() }
            return
        }

        if debug {
            print("→ \(action)")
        } else if ClickPoster.isTrusted {
            ClickPoster.post(action, dragOrigin: detector.dragOrigin)
        }
    }

    /// Resets the detector and lets go of the button if a drag was in progress.
    private func releaseDrag() {
        if detector.reset(), !debug, ClickPoster.isTrusted {
            ClickPoster.post(.dragEnd)
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
        let threeFinger = NSMenuItem(title: "Three-finger hold", action: nil, keyEquivalent: "")
        let threeFingerMenu = NSMenu()
        for action in ThreeFingerAction.allCases {
            let option = item(action.title, #selector(pickThreeFingerAction(_:)), checked: Settings.threeFingerAction == action)
            option.representedObject = action.rawValue
            threeFingerMenu.addItem(option)
        }
        threeFinger.submenu = threeFingerMenu
        menu.addItem(threeFinger)
        menu.addItem(item("Double tap → double click", #selector(toggleDoubleTap), checked: Settings.doubleTap))
        menu.addItem(item("Tap, then hold → drag", #selector(toggleDrag), checked: Settings.tapAndDrag))
        menu.addItem(item("Rest finger → drag", #selector(toggleHoldDrag), checked: Settings.holdToDrag))
        menu.addItem(item("Two-finger swipe up/down → Mission Control", #selector(toggleMissionControl), checked: Settings.missionControlSwipe))
        menu.addItem(item("Two-finger pinch → zoom", #selector(togglePinch), checked: Settings.pinchZoom))
        menu.addItem(item("One-finger swipe left/right → back/forward", #selector(toggleNavigation), checked: Settings.navigationSwipe))
        menu.addItem(.separator())

        let mouseCount = monitor?.activeDeviceCount ?? 0
        let mouseLine = mouseCount > 0 ? "Magic Mouse detected" : "No Magic Mouse found"
        menu.addItem(withTitle: mouseLine, action: nil, keyEquivalent: "").isEnabled = false

        if !ClickPoster.isTrusted {
            menu.addItem(item("Grant Accessibility permission…", #selector(openSetup)))
        }
        menu.addItem(item("Launch at login", #selector(toggleLaunchAtLogin), checked: LoginItem.isEnabled))
        menu.addItem(.separator())
        menu.addItem(item("Settings…", #selector(openSettings), key: ","))
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
        releaseDrag()
    }

    @objc private func toggleLeft() {
        Settings.singleFingerLeftClick.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func toggleRight() {
        Settings.twoFingerRightClick.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func pickThreeFingerAction(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let action = ThreeFingerAction(rawValue: raw) else { return }
        Settings.threeFingerAction = action
        detector.config = Settings.tapConfig
    }

    @objc private func toggleDoubleTap() {
        Settings.doubleTap.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func toggleDrag() {
        Settings.tapAndDrag.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func toggleHoldDrag() {
        Settings.holdToDrag.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func toggleMissionControl() {
        Settings.missionControlSwipe.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func toggleNavigation() {
        Settings.navigationSwipe.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func togglePinch() {
        Settings.pinchZoom.toggle()
        detector.config = Settings.tapConfig
    }

    @objc private func openSetup() {
        ClickPoster.requestTrust()
        settingsWindow.show(tab: .setup)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.set(!LoginItem.isEnabled)
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
