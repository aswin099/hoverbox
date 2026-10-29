import Foundation
import HoverboxCore
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let newShelf = Self("newShelf", default: .init(.space, modifiers: [.option, .shift]))
}

/// UserDefaults keys and typed accessors. Views use the same keys through @AppStorage.
enum Prefs {
    static let shakeEnabled = "shakeEnabled"
    static let sensitivity = "shakeSensitivity"
    static let excludedApps = "excludedApps"
    static let keepAfterDragOut = "keepAfterDragOut"
    /// How solid the shelf background is: 0 is clear glass, 1 is the opaque window colour.
    static let backgroundOpacity = "shelfBackgroundOpacity"
    static let defaultBackgroundOpacity = 0.55

    static func register() {
        UserDefaults.standard.register(defaults: [
            shakeEnabled: true,
            sensitivity: ShakeDetector.Sensitivity.medium.rawValue,
            excludedApps: [String](),
            keepAfterDragOut: false,
            backgroundOpacity: defaultBackgroundOpacity,
        ])
    }

    static var excludedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: excludedApps) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: excludedApps) }
    }

    static var shakeSensitivity: ShakeDetector.Sensitivity {
        ShakeDetector.Sensitivity(rawValue: UserDefaults.standard.string(forKey: sensitivity) ?? "") ?? .medium
    }

    static var shouldKeepAfterDragOut: Bool { UserDefaults.standard.bool(forKey: keepAfterDragOut) }

    static func shakeRules(paused: Bool) -> ShakeRules {
        ShakeRules(isEnabled: UserDefaults.standard.bool(forKey: shakeEnabled) && !paused,
                   excludedBundleIDs: Set(excludedBundleIDs))
    }
}
