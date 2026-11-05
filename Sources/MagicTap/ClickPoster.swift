import AppKit
import ApplicationServices
import Carbon.HIToolbox
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

    /// Posts the mouse events for a tap action. `dragOrigin` is where a drag
    /// must start (where the touch began, not where the cursor is by now).
    static func post(_ action: TapAction, dragOrigin: CGPoint = .zero) {
        switch action {
        case .leftClick:
            missionControlOpen = false
            send(.leftMouseDown, button: .left, at: cursorLocation)
            send(.leftMouseUp, button: .left, at: cursorLocation)
        case .doubleClick:
            missionControlOpen = false
            send(.leftMouseDown, button: .left, at: cursorLocation, clickCount: 2)
            send(.leftMouseUp, button: .left, at: cursorLocation, clickCount: 2)
        case .rightClick:
            send(.rightMouseDown, button: .right, at: cursorLocation)
            send(.rightMouseUp, button: .right, at: cursorLocation)
        case .dragStart:
            send(.leftMouseDown, button: .left, at: dragOrigin)
            // Catch the cursor up to where the mouse has moved since the touch.
            sendDragged()
        case .dragEnd:
            send(.leftMouseUp, button: .left, at: cursorLocation)
        case .missionControl:
            missionControlOpen = true
            DispatchQueue.main.async {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
            }
        case .missionControlClose:
            // Escape would go to the frontmost app if Mission Control isn't
            // actually open, so only send it after we opened it ourselves.
            guard missionControlOpen else { return }
            missionControlOpen = false
            sendKey(CGKeyCode(kVK_Escape), flags: [])
        case let .magnify(amount, phase):
            sendMagnify(Double(amount), phase)
        }
    }

    /// True after we opened Mission Control and until a click or Escape.
    static var missionControlOpen = false

    private static func sendKey(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        for down in [true, false] {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            event.flags = flags
            event.post(tap: .cghidEventTap)
        }
    }

    /// Posts a trackpad-style magnify gesture. These are undocumented CGEvent
    /// fields (type 29 = gesture, field 110 = gesture type, 8 = magnify,
    /// 113 = magnification, 132 = phase), which AppKit turns into
    /// `NSEvent.magnify` and browsers into smooth pinch zoom.
    private static func sendMagnify(_ amount: Double, _ phase: GesturePhase) {
        guard let event = CGEvent(source: nil),
              let type = CGEventType(rawValue: 29),
              let gestureType = CGEventField(rawValue: 110),
              let magnification = CGEventField(rawValue: 113),
              let phaseField = CGEventField(rawValue: 132) else { return }
        event.type = type
        event.setIntegerValueField(gestureType, value: 8)
        event.setDoubleValueField(magnification, value: amount)
        let value: Int64
        switch phase {
        case .began: value = 1
        case .changed: value = 2
        case .ended: value = 4
        }
        event.setIntegerValueField(phaseField, value: value)
        event.post(tap: .cghidEventTap)
    }

    /// While dragging, tells apps the pointer moved with the button down. The
    /// system may report real mouse motion as plain moves for synthetic presses.
    static func sendDragged() {
        send(.leftMouseDragged, button: .left, at: cursorLocation)
    }

    private static let source = CGEventSource(stateID: .hidSystemState)
    /// Last position we posted, to give drag events a real delta.
    private static var lastPosted: CGPoint?

    private static func send(
        _ type: CGEventType, button: CGMouseButton, at location: CGPoint, clickCount: Int64 = 1
    ) {
        guard let event = CGEvent(
            mouseEventSource: source, mouseType: type,
            mouseCursorPosition: location, mouseButton: button
        ) else { return }
        if type != .leftMouseDragged {
            ignoreButtonEventsUntil = Date().addingTimeInterval(0.15)
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        // Text views (unlike Finder) read the motion and pressure of a drag.
        if type == .leftMouseDragged {
            let from = lastPosted ?? location
            event.setIntegerValueField(.mouseEventDeltaX, value: Int64((location.x - from.x).rounded()))
            event.setIntegerValueField(.mouseEventDeltaY, value: Int64((location.y - from.y).rounded()))
        }
        event.setDoubleValueField(.mouseEventPressure, value: type == .leftMouseUp ? 0 : 1)
        lastPosted = type == .leftMouseUp ? nil : location
        event.post(tap: .cghidEventTap)
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
