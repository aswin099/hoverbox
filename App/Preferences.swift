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
    static let favouritesKey = "favourites"
    static let watchedFoldersKey = "watchedFolders"
    static let screenshotsKey = "screenshotsToShelf"
    /// Colour new shelves start with ("" for none).
    static let newShelfColorKey = "newShelfColor"

    static func register() {
        UserDefaults.standard.register(defaults: [
            shakeEnabled: true,
            sensitivity: ShakeDetector.Sensitivity.medium.rawValue,
            excludedApps: [String](),
            keepAfterDragOut: false,
            backgroundOpacity: defaultBackgroundOpacity,
            favouritesKey: [String](),
            watchedFoldersKey: [String](),
            screenshotsKey: false,
        ])
    }

    static var excludedBundleIDs: [String] {
        get { UserDefaults.standard.stringArray(forKey: excludedApps) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: excludedApps) }
    }

    /// Folders and apps to drop onto, as paths.
    static var favourites: [String] {
        get { UserDefaults.standard.stringArray(forKey: favouritesKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: favouritesKey) }
    }

    /// Folders whose new files open a shelf.
    static var watchedFolders: [String] {
        get { UserDefaults.standard.stringArray(forKey: watchedFoldersKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: watchedFoldersKey) }
    }

    static var newShelfColor: ShelfColor? {
        ShelfColor(rawValue: UserDefaults.standard.string(forKey: newShelfColorKey) ?? "")
    }

    static var screenshotsToShelf: Bool {
        get { UserDefaults.standard.bool(forKey: screenshotsKey) }
        set { UserDefaults.standard.set(newValue, forKey: screenshotsKey) }
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
