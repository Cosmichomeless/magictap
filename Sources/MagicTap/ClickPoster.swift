import ApplicationServices
import CoreGraphics
import Foundation
import MagicTapCore

enum ClickPoster {
    /// Time window during which button events are our own and must not be
    /// mistaken for a physical click by the monitor.
    private(set) static var ignoreButtonEventsUntil: Date = .distantPast

    static var cursorLocation: CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static func post(_ action: TapAction) {
        let location = cursorLocation
        let (button, downType, upType): (CGMouseButton, CGEventType, CGEventType) = {
            switch action {
            case .leftClick: return (.left, .leftMouseDown, .leftMouseUp)
            case .rightClick: return (.right, .rightMouseDown, .rightMouseUp)
            }
        }()

        ignoreButtonEventsUntil = Date().addingTimeInterval(0.15)
        for type in [downType, upType] {
            guard let event = CGEvent(
                mouseEventSource: nil, mouseType: type,
                mouseCursorPosition: location, mouseButton: button
            ) else { continue }
            event.setIntegerValueField(.mouseEventClickState, value: 1)
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: Accessibility permission (required to post synthetic events)

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security.
    @discardableResult
    static func requestTrust() -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
