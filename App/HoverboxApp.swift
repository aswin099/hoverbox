import SwiftUI

@main
struct HoverboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // The menu bar icon and the Settings window are AppKit (see StatusItemController and
        // SettingsWindow), so the icon can take drops; this scene only satisfies SwiftUI's App.
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    private let services = ServiceProvider()

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            statusItem = StatusItemController(model: AppModel.shared)
        }
        NSApp.servicesProvider = services
        NSUpdateDynamicServices()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            urls.forEach(AppModel.shared.handle(url:))
        }
    }
}

/// Handles "Add to Hoverbox" from Finder's right-click menu, the Services menu, or its
/// shortcut (⇧⌘B by default; change it in System Settings › Keyboard › Keyboard Shortcuts › Services).
final class ServiceProvider: NSObject {
    @objc func addToShelf(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        let read = DropReader.read(pasteboard) { items in
            MainActor.assumeIsolated { AppModel.shared.addFromService(items) }
        }
        if !read { error.pointee = "There was nothing Hoverbox could hold." }
    }
}
