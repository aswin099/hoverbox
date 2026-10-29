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

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            statusItem = StatusItemController(model: AppModel.shared)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            urls.forEach(AppModel.shared.handle(url:))
        }
    }
}
