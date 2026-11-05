import Foundation
import MagicTapCore

/// User preferences, persisted in UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let enabled = "enabled"
        static let leftTap = "singleFingerLeftClick"
        static let rightTap = "twoFingerRightClick"
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

    static var tapConfig: TapConfig {
        var config = TapConfig()
        config.singleFingerLeftClick = singleFingerLeftClick
        config.twoFingerRightClick = twoFingerRightClick
        return config
    }
}
