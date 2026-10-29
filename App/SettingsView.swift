import HoverboxCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @AppStorage(Prefs.shakeEnabled) private var shakeEnabled = true
    @AppStorage(Prefs.sensitivity) private var sensitivity = ShakeDetector.Sensitivity.medium.rawValue
    @AppStorage(Prefs.keepAfterDragOut) private var keepAfterDragOut = false
    @AppStorage(Prefs.backgroundOpacity) private var backgroundOpacity = Prefs.defaultBackgroundOpacity
    @State private var excluded = Prefs.excludedBundleIDs
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var favourites = Prefs.favourites
    @State private var watchedFolders = Prefs.watchedFolders
    @State private var screenshots = Prefs.screenshotsToShelf

    var body: some View {
        Form {
            Section("Opening a shelf") {
                Toggle("Shake the pointer while dragging to open a shelf", isOn: $shakeEnabled)
                Picker("Shake sensitivity", selection: $sensitivity) {
                    Text("Low: big, deliberate shakes").tag(ShakeDetector.Sensitivity.low.rawValue)
                    Text("Medium").tag(ShakeDetector.Sensitivity.medium.rawValue)
                    Text("High: small shakes are enough").tag(ShakeDetector.Sensitivity.high.rawValue)
                }
                .disabled(!shakeEnabled)
                KeyboardShortcuts.Recorder("New shelf shortcut:", name: .newShelf)
            }

            Section {
                LabeledContent("Shelf background") {
                    HStack(spacing: 8) {
                        Text("Glass").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $backgroundOpacity, in: 0...1)
                            .frame(width: 180)
                            .accessibilityLabel("Shelf background, from glass to solid")
                            .accessibilityValue("\(Int(backgroundOpacity * 100)) percent solid")
                        Text("Solid").font(.caption).foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("Changes every open shelf as you drag. Thumbnails and text always stay fully visible.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Keep items on the shelf after dragging them out", isOn: $keepAfterDragOut)
            } header: {
                Text("Shelves")
            } footer: {
                Text("Hold Shift as you drop to keep items just for that drag. Pinned shelves always keep their items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                if excluded.isEmpty {
                    Text("None. Shake works in every app.")
                        .foregroundStyle(.secondary)
                }
                ForEach(excluded, id: \.self) { bundleID in
                    HStack {
                        AppLabel(bundleID: bundleID)
                        Spacer()
                        Button("Remove") { setExcluded(excluded.filter { $0 != bundleID }) }
                    }
                }
                Menu("Add App…") {
                    ForEach(runningApps, id: \.bundleIdentifier) { app in
                        Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                            if let id = app.bundleIdentifier { setExcluded(excluded + [id]) }
                        }
                    }
                }
                .fixedSize()
            } header: {
                Text("Don't open shelves when shaking in")
            } footer: {
                Text("Useful for games and design tools where you drag a lot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                ForEach(favourites, id: \.self) { path in
                    HStack {
                        PathLabel(path: path)
                        Spacer()
                        Button("Remove") { setFavourites(favourites.filter { $0 != path }) }
                    }
                }
                HStack {
                    Button("Add Folder…") { if let paths = choose(apps: false) { setFavourites(favourites + paths) } }
                    Button("Add App…") { if let paths = choose(apps: true) { setFavourites(favourites + paths) } }
                }
            } header: {
                Text("Favourites")
            } footer: {
                Text("While you drag over a shelf, favourites appear as drop targets: folders get a copy (hold ⌘ to move), apps open the files. They're also under Copy To, Move To and Open With in the shelf menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Put new screenshots on a shelf", isOn: $screenshots)
                    .onChange(of: screenshots) { _, on in
                        Prefs.screenshotsToShelf = on
                        AppModel.shared.reloadFolderWatchers()
                    }
                ForEach(watchedFolders, id: \.self) { path in
                    HStack {
                        PathLabel(path: path)
                        Spacer()
                        Button("Remove") { setWatched(watchedFolders.filter { $0 != path }) }
                    }
                }
                Button("Watch a Folder…") { if let paths = choose(apps: false) { setWatched(watchedFolders + paths) } }
            } header: {
                Text("Automatic shelves")
            } footer: {
                Text("New screenshots, or new files in a watched folder (such as Downloads), appear on a shelf in the top-right corner without interrupting you. Screenshots are saved to \(ScreenshotDetector.screenshotFolder.lastPathComponent).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                Text("Hoverbox asks for no permissions and never connects to the internet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 680)
        .onAppear { NSApp.activate(ignoringOtherApps: true) }
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil
                && $0.bundleIdentifier != Bundle.main.bundleIdentifier
                && !excluded.contains($0.bundleIdentifier!) }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func setFavourites(_ list: [String]) {
        var seen = Set<String>()
        favourites = list.filter { seen.insert($0).inserted }
        Prefs.favourites = favourites
    }

    private func setWatched(_ list: [String]) {
        var seen = Set<String>()
        watchedFolders = list.filter { seen.insert($0).inserted }
        Prefs.watchedFolders = watchedFolders
        AppModel.shared.reloadFolderWatchers()
    }

    /// Asks for folders, or for apps in /Applications.
    private func choose(apps: Bool) -> [String]? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = !apps
        panel.canChooseFiles = apps
        if apps {
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
        }
        panel.prompt = apps ? "Add App" : "Choose"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls.map(\.path)
    }

    private func setExcluded(_ list: [String]) {
        excluded = Array(Set(list)).sorted()
        Prefs.excludedBundleIDs = excluded
    }
}

/// Icon and name for a folder or app at a path.
private struct PathLabel: View {
    let path: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 18, height: 18)
            Text(FileManager.default.displayName(atPath: path))
            Text((path as NSString).abbreviatingWithTildeInPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

/// Icon and name for an app, looked up from its bundle ID.
private struct AppLabel: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            Image(nsImage: url.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSImage())
                .resizable()
                .frame(width: 18, height: 18)
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}
