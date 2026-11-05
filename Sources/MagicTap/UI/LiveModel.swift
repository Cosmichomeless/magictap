import Foundation
import MagicTapCore
import SwiftUI

/// What the window shows live: the fingers on the mouse and recent gestures.
/// `AppDelegate` only publishes while the window is visible.
final class LiveModel: ObservableObject {
    static let shared = LiveModel()

    struct Event: Identifiable {
        let id = UUID()
        let text: String
        let time: Date
    }

    @Published var touches: [TouchPoint] = []
    @Published var events: [Event] = []

    /// Set by `AppDelegate`; read by the Setup tab.
    var mouseCount: () -> Int = { 0 }

    func push(touches: [TouchPoint], action: TapAction?) {
        self.touches = touches
        guard let text = action?.liveDescription else { return }
        events.insert(Event(text: text, time: Date()), at: 0)
        if events.count > 8 { events.removeLast(events.count - 8) }
    }

    func clear() {
        touches = []
        events = []
    }
}

private extension TapAction {
    /// Pinch updates arrive every frame; only the start and end are worth listing.
    var liveDescription: String? {
        switch self {
        case .leftClick: return "Left click"
        case .doubleClick: return "Double click"
        case .rightClick: return "Right click"
        case .middleClick: return "Middle click"
        case .threeFingerTap: return "Three-finger hold"
        case .dragStart: return "Drag started"
        case .dragEnd: return "Drag ended"
        case .missionControl: return "Open Mission Control"
        case .missionControlClose: return "Close Mission Control"
        case let .navigate(_, phase):
            switch phase {
            case .began: return "Back / forward swipe started"
            case .changed: return nil
            case .ended: return "Back / forward swipe ended"
            }
        case let .magnify(_, phase):
            switch phase {
            case .began: return "Pinch started"
            case .changed: return nil
            case .ended: return "Pinch ended"
            }
        }
    }
}

/// Which tab the window shows (the menu and first launch can pick one).
final class Navigation: ObservableObject {
    static let shared = Navigation()
    enum Tab: Hashable { case gestures, live, setup }
    @Published var tab: Tab = .gestures
}
