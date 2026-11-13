import Foundation
import MagicTapCore

/// What a three-finger hold does (configurable; Show Desktop by default).
enum ThreeFingerAction: String, CaseIterable, Identifiable {
    case showDesktop, middleClick, missionControl, none
    var id: String { rawValue }
    var title: String {
        switch self {
        case .showDesktop: return "Show Desktop"
        case .middleClick: return "Middle click"
        case .missionControl: return "Mission Control"
        case .none: return "Do nothing"
        }
    }
}

/// User preferences, persisted in UserDefaults.
enum Settings {
    private static let defaults = UserDefaults.standard

    /// UserDefaults keys. The settings window binds to them with `@AppStorage`,
    /// so the menu and the window stay in sync without extra plumbing.
    enum Key {
        static let enabled = "enabled"
        static let leftTap = "singleFingerLeftClick"
        static let rightTap = "twoFingerRightClick"
        static let clickFeedback = "clickFeedback"
        static let pulseSize = "pulseSize"
        static let clickSound = "clickSound"
        static let soundVolume = "soundVolume"
        static let middleTap = "threeFingerMiddleClick"
        static let threeFingerAction = "threeFingerAction"
        static let tapAndDrag = "tapAndDrag"
        static let holdToDrag = "holdToDrag"
        static let doubleTap = "doubleTap"
        static let missionControlSwipe = "missionControlSwipe"
        static let pinchZoom = "pinchZoom"
        static let navigationSwipe = "navigationSwipe"
        // Tuning (sliders in the settings window).
        static let maxTapDuration = "maxTapDuration"
        static let doubleTapWindow = "doubleTapWindow"
        static let holdToDragAfter = "holdToDragAfter"
        static let swipeDistance = "swipeDistance"
        static let pinchGain = "pinchGain"
        static let edgeMargin = "edgeMargin"
        static let tuningKeys = [
            maxTapDuration, doubleTapWindow, holdToDragAfter, swipeDistance,
            pinchGain, edgeMargin,
        ]
    }

    /// Back to the built-in thresholds.
    static func resetTuning() {
        for key in Key.tuningKeys { defaults.removeObject(forKey: key) }
    }

    private static func number(_ key: String, default value: Double) -> Double {
        defaults.object(forKey: key) as? Double ?? value
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

    /// The cursor pulses when MagicTap sends a click.
    static var clickFeedback: Bool {
        get { defaults.object(forKey: Key.clickFeedback) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.clickFeedback) }
    }

    /// How much bigger the cursor gets at the peak of the pulse (1.6 = 60 % bigger).
    static let defaultPulseSize = 1.6
    static let pulseSizeRange = 1.1...2.5
    static var pulseSize: Double {
        let value = number(Key.pulseSize, default: defaultPulseSize)
        return min(max(value, pulseSizeRange.lowerBound), pulseSizeRange.upperBound)
    }

    /// A soft click sound plays when MagicTap sends a click.
    static var clickSound: Bool {
        get { defaults.object(forKey: Key.clickSound) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.clickSound) }
    }

    static let defaultSoundVolume = 0.5
    static var soundVolume: Double {
        min(max(number(Key.soundVolume, default: defaultSoundVolume), 0), 1)
    }

    static var threeFingerMiddleClick: Bool {
        get { defaults.object(forKey: Key.middleTap) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.middleTap) }
    }

    /// What a three-finger hold does. Show Desktop unless the user picked another.
    static var threeFingerAction: ThreeFingerAction {
        get { defaults.string(forKey: Key.threeFingerAction).flatMap(ThreeFingerAction.init) ?? .showDesktop }
        set { defaults.set(newValue.rawValue, forKey: Key.threeFingerAction) }
    }

    static var tapAndDrag: Bool {
        get { defaults.object(forKey: Key.tapAndDrag) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.tapAndDrag) }
    }

    static var holdToDrag: Bool {
        get { defaults.object(forKey: Key.holdToDrag) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.holdToDrag) }
    }

    static var doubleTap: Bool {
        get { defaults.object(forKey: Key.doubleTap) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.doubleTap) }
    }

    static var missionControlSwipe: Bool {
        get { defaults.object(forKey: Key.missionControlSwipe) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.missionControlSwipe) }
    }

    static var pinchZoom: Bool {
        get { defaults.object(forKey: Key.pinchZoom) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.pinchZoom) }
    }

    static var navigationSwipe: Bool {
        get { defaults.object(forKey: Key.navigationSwipe) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.navigationSwipe) }
    }

    /// Pixels of synthetic scroll per unit of finger travel (the sensor is 1 wide).
    /// Chrome navigates when the swipe passes a fraction of the window width.
    static var navigationGain: Double { 1500 }

    static var tapConfig: TapConfig {
        var config = TapConfig()
        config.singleFingerLeftClick = singleFingerLeftClick
        config.twoFingerRightClick = twoFingerRightClick
        config.threeFingerMiddleClick = threeFingerMiddleClick
        config.threeFingerTap = threeFingerAction != .none
        config.tapAndDrag = tapAndDrag
        config.holdToDrag = holdToDrag
        config.doubleTap = doubleTap
        config.missionControlSwipe = missionControlSwipe
        config.pinchZoom = pinchZoom
        config.navigationSwipe = navigationSwipe
        let base = TapConfig()
        config.maxTapDuration = number(Key.maxTapDuration, default: base.maxTapDuration)
        config.doubleTapWindow = number(Key.doubleTapWindow, default: base.doubleTapWindow)
        // Must stay below `restingAfter`, which stops counting a resting finger.
        config.holdToDragAfter = min(number(Key.holdToDragAfter, default: base.holdToDragAfter), config.restingAfter - 0.02)
        config.swipeDistance = Float(number(Key.swipeDistance, default: Double(base.swipeDistance)))
        config.pinchGain = Float(number(Key.pinchGain, default: Double(base.pinchGain)))
        config.edgeMargin = Float(number(Key.edgeMargin, default: Double(base.edgeMargin)))
        return config
    }
}
