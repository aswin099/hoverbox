import KeyboardShortcuts
import SwiftUI

@main
struct HoverboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.isShakePaused ? "shippingbox" : "shippingbox.fill")
        }
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { AppModel.shared.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            AppModel.shared.start()
            urls.forEach(AppModel.shared.handle(url:))
        }
    }
}

@MainActor
struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Button("New Shelf") { model.newShelf(at: NSEvent.mouseLocation) }
            .keyboardShortcut(KeyboardShortcuts.getShortcut(for: .newShelf)?.toSwiftUI)
        if !model.shelves.isEmpty {
            Section("Open Shelves") {
                ForEach(model.shelves) { controller in
                    Button((controller.shelf.isPinned ? "📌 " : "") + controller.shelf.title) {
                        controller.bringToFront()
                    }
                }
            }
            Button("Close Unpinned Shelves") { model.closeUnpinnedShelves() }
                .disabled(!model.shelves.contains { !$0.shelf.isPinned })
        }
        Divider()
        Toggle("Pause Shake to Open", isOn: $model.isShakePaused)
        Divider()
        SettingsLink { Text("Settings…") }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Hoverbox") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
