import AppKit
import Foundation
import HoverboxCore
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let newShelf = Self("newShelf", default: .init(.space, modifiers: [.option, .shift]))
    static let nextShelf = Self("nextShelf", default: .init(.tab, modifiers: [.option, .shift]))
    // Actions on the shelf you used last; no defaults, so they never clash with other apps.
    static let actionZip = Self("actionZip")
    static let actionText = Self("actionExtractText")
    static let actionCompress = Self("actionCompressImages")
    static let actionResize = Self("actionResizeHalf")
    static let actionAirDrop = Self("actionAirDrop")
    static let actionShare = Self("actionShare")
}

/// Where shelves opened from the shortcut, the menu bar or Finder appear. Shelves opened by
/// shaking or holding still always appear at the pointer, where the drag is.
enum ShelfPlacement: String, CaseIterable {
    case pointer, topRight, center
}

enum ShelfAppearance: String, CaseIterable {
    case system, light, dark

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// What opens a shelf during a drag.
enum OpenTrigger: String, CaseIterable {
    case shake, dwell, both

    var usesShake: Bool { self != .dwell }
    var usesDwell: Bool { self != .shake }
}

/// UserDefaults keys and typed accessors. Views use the same keys through @AppStorage.
enum Prefs {
    static let shakeEnabled = "shakeEnabled"
    static let sensitivity = "shakeSensitivity"
    static let excludedApps = "excludedApps"
    static let keepAfterDragOut = "keepAfterDragOut"
    static let openTriggerKey = "openTrigger"
    static let dwellDelayKey = "dwellDelay"
    /// How solid the shelf background is: 0 is clear glass, 1 is the opaque window colour.
    static let backgroundOpacity = "shelfBackgroundOpacity"
    static let defaultBackgroundOpacity = 0.55
    static let favouritesKey = "favourites"
    static let watchedFoldersKey = "watchedFolders"
    static let screenshotsKey = "screenshotsToShelf"
    /// Colour new shelves start with ("" for none).
    static let newShelfColorKey = "newShelfColor"
    static let keepCopiesKey = "keepCopies"
    static let placementKey = "newShelfPlacement"
    static let appearanceKey = "shelfAppearance"
    static let largeShelvesKey = "largeShelves"
    static let openExpandedKey = "openExpanded"

    static func register() {
        UserDefaults.standard.register(defaults: [
            shakeEnabled: true,
            sensitivity: ShakeDetector.Sensitivity.medium.rawValue,
            excludedApps: [String](),
            keepAfterDragOut: false,
            openTriggerKey: OpenTrigger.shake.rawValue,
            dwellDelayKey: 1.0,
            backgroundOpacity: defaultBackgroundOpacity,
            favouritesKey: [String](),
            watchedFoldersKey: [String](),
            screenshotsKey: false,
            keepCopiesKey: false,
            placementKey: ShelfPlacement.pointer.rawValue,
            appearanceKey: ShelfAppearance.system.rawValue,
            largeShelvesKey: false,
            openExpandedKey: false,
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

    static var openTrigger: OpenTrigger {
        OpenTrigger(rawValue: UserDefaults.standard.string(forKey: openTriggerKey) ?? "") ?? .shake
    }

    static var dwellDelay: TimeInterval {
        let value = UserDefaults.standard.double(forKey: dwellDelayKey)
        return value > 0 ? value : 1.0
    }

    static var shakeSensitivity: ShakeDetector.Sensitivity {
        ShakeDetector.Sensitivity(rawValue: UserDefaults.standard.string(forKey: sensitivity) ?? "") ?? .medium
    }

    static var shouldKeepAfterDragOut: Bool { UserDefaults.standard.bool(forKey: keepAfterDragOut) }
    /// Copy mode: files dropped on a shelf are copied, so originals are never touched.
    static var keepCopies: Bool { UserDefaults.standard.bool(forKey: keepCopiesKey) }
    static var placement: ShelfPlacement {
        ShelfPlacement(rawValue: UserDefaults.standard.string(forKey: placementKey) ?? "") ?? .pointer
    }
    static var appearance: ShelfAppearance {
        ShelfAppearance(rawValue: UserDefaults.standard.string(forKey: appearanceKey) ?? "") ?? .system
    }
    static var largeShelves: Bool { UserDefaults.standard.bool(forKey: largeShelvesKey) }
    static var openExpanded: Bool { UserDefaults.standard.bool(forKey: openExpandedKey) }

    static func shakeRules(paused: Bool) -> ShakeRules {
        ShakeRules(isEnabled: UserDefaults.standard.bool(forKey: shakeEnabled) && !paused,
                   excludedBundleIDs: Set(excludedBundleIDs))
    }
}
