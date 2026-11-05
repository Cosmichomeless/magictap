import AppKit
import SwiftUI

/// Hosts the SwiftUI settings in a regular window. The app has no Dock icon
/// (`LSUIElement`), so it must be brought to the front by hand.
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    /// Called when the window opens (true) or closes (false), so the app only
    /// feeds the live viewer while someone is looking.
    var onVisibilityChange: ((Bool) -> Void)?

    func show(tab: Navigation.Tab? = nil) {
        if let tab { Navigation.shared.tab = tab }
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView())
            let window = NSWindow(contentViewController: controller)
            window.title = "MagicTap"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        onVisibilityChange?(true)
    }

    func windowWillClose(_ notification: Notification) {
        onVisibilityChange?(false)
    }
}
