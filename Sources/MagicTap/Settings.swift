import Foundation
import MagicTapCore

/// User preferences, persisted in UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let leftTap = "singleFingerLeftClick"
        static let rightTap = "twoFingerRightClick"
        static let tapAndDrag = "tapAndDrag"
        static let holdToDrag = "holdToDrag"
        static let missionControlSwipe = "missionControlSwipe"
        static let pinchZoom = "pinchZoom"
    }

    static var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    static var singleFingerLeftClick: Bool {
        get { defaults.object(forKey: Key.leftTap) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.leftTap) }
    }

    static var twoFingerRightClick: Bool {
        get { defaults.object(forKey: Key.rightTap) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.rightTap) }
    }

    static var tapAndDrag: Bool {
        get { defaults.object(forKey: Key.tapAndDrag) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.tapAndDrag) }
    }

    static var holdToDrag: Bool {
        get { defaults.object(forKey: Key.holdToDrag) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.holdToDrag) }
    }

    static var missionControlSwipe: Bool {
        get { defaults.object(forKey: Key.missionControlSwipe) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.missionControlSwipe) }
    }

    static var pinchZoom: Bool {
        get { defaults.object(forKey: Key.pinchZoom) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.pinchZoom) }
    }

    static var tapConfig: TapConfig {
        var config = TapConfig()
        config.singleFingerLeftClick = singleFingerLeftClick
        config.twoFingerRightClick = twoFingerRightClick
        config.tapAndDrag = tapAndDrag
        config.holdToDrag = holdToDrag
        config.missionControlSwipe = missionControlSwipe
        config.pinchZoom = pinchZoom
        return config
    }
}
