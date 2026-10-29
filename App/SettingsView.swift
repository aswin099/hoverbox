import HoverboxCore
import KeyboardShortcuts
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

/// The Settings window: native toolbar tabs (like System Settings panes and Tuck's
/// Settings), each tab a SwiftUI form. Built with AppKit's tab controller because the
/// menu bar icon is AppKit and can't open SwiftUI's Settings scene.
@MainActor
enum SettingsWindow {
    static func make() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = [.crossfade, .allowUserInteraction]
        func add(_ title: String, _ symbol: String, _ view: some View) {
            let host = NSHostingController(rootView: view)
            host.sizingOptions = .preferredContentSize
            host.title = title  // The tab controller shows the selected tab's title in the window.
            let item = NSTabViewItem(viewController: host)
            item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("General", "gearshape", GeneralSettings())
        add("Shake", "hand.draw", ShakeSettings())
        add("Shelves", "square.stack", ShelvesSettings())
        add("Favourites", "star", FavouritesSettings())
        add("Automatic", "bolt.badge.clock", AutomaticSettings())
        add("About", "info.circle", AboutSettings())

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

// MARK: - General

@MainActor
private struct GeneralSettings: View {
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Keyboard shortcuts") {
                KeyboardShortcuts.Recorder("New shelf at the pointer", name: .newShelf)
            }

            Section("Startup") {
                Toggle("Open Hoverbox at login", isOn: $launchAtLogin)
            }

            Section {
                LabeledContent("Permissions") {
                    Label("None needed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                LabeledContent("Network") {
                    Label("Never used", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Shelves hold references to your files, not copies. Nothing leaves your Mac unless you share or AirDrop it.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
        .onChange(of: launchAtLogin) { _, enabled in
            do {
                if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

// MARK: - Shake

@MainActor
private struct ShakeSettings: View {
    @AppStorage(Prefs.shakeEnabled) private var shakeEnabled = true
    @AppStorage(Prefs.sensitivity) private var sensitivity = ShakeDetector.Sensitivity.medium.rawValue
    @State private var excluded = Prefs.excludedBundleIDs
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $shakeEnabled) {
                    Text("Shake the pointer while dragging to open a shelf")
                    Text("Works in every app and needs no permissions. You can always use the shortcut or the menu bar icon instead.")
                }
                Picker("Sensitivity", selection: $sensitivity) {
                    Text("Low: big, deliberate shakes").tag(ShakeDetector.Sensitivity.low.rawValue)
                    Text("Medium").tag(ShakeDetector.Sensitivity.medium.rawValue)
                    Text("High: small shakes are enough").tag(ShakeDetector.Sensitivity.high.rawValue)
                }
                .disabled(!shakeEnabled)
            } footer: {
                Text("If shelves open when you don't want them (for example with a tremor), choose Low, or turn shaking off for some apps below.")
                    .settingsFootnote()
            }

            Section {
                ItemList(items: excluded, selection: $selection, empty: "Shaking works in every app") { bundleID in
                    AppRow(bundleID: bundleID)
                }
                ListButtons(canRemove: selection != nil, remove: removeSelected) {
                    Button("Choose App…") { chooseApps() }
                    let running = runningApps
                    if !running.isEmpty {
                        Divider()
                        ForEach(running, id: \.bundleIdentifier) { app in
                            Button(app.localizedName ?? app.bundleIdentifier ?? "App") {
                                if let id = app.bundleIdentifier { setExcluded(excluded + [id]) }
                            }
                        }
                    }
                }
            } header: {
                Text("Don't open shelves when shaking in")
            } footer: {
                Text("Useful for games and design tools where you drag a lot.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 430)
    }

    private var runningApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications
            .filter { app in
                guard app.activationPolicy == .regular, let id = app.bundleIdentifier else { return false }
                return id != Bundle.main.bundleIdentifier && !excluded.contains(id)
            }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
    }

    private func chooseApps() {
        let ids = choose(apps: true)?.compactMap { Bundle(path: $0)?.bundleIdentifier } ?? []
        setExcluded(excluded + ids)
    }

    private func removeSelected() {
        guard let selection else { return }
        setExcluded(excluded.filter { $0 != selection })
        self.selection = nil
    }

    private func setExcluded(_ list: [String]) {
        excluded = Array(Set(list)).sorted()
        Prefs.excludedBundleIDs = excluded
    }
}

// MARK: - Shelves

@MainActor
private struct ShelvesSettings: View {
    @AppStorage(Prefs.backgroundOpacity) private var backgroundOpacity = Prefs.defaultBackgroundOpacity
    @AppStorage(Prefs.newShelfColorKey) private var newShelfColor = ""
    @AppStorage(Prefs.keepAfterDragOut) private var keepAfterDragOut = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Background") {
                    HStack(spacing: 8) {
                        Text("Glass").font(.caption).foregroundStyle(.secondary)
                        Slider(value: $backgroundOpacity, in: 0...1)
                            .frame(width: 180)
                            .accessibilityLabel("Shelf background, from glass to solid")
                            .accessibilityValue("\(Int(backgroundOpacity * 100)) percent solid")
                        Text("Solid").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Picker("Colour for new shelves", selection: $newShelfColor) {
                    Text("None").tag("")
                    ForEach(ShelfColor.allCases, id: \.rawValue) { option in
                        Label { Text(option.displayName) } icon: { Image(nsImage: option.swatch()) }
                            .tag(option.rawValue)
                    }
                }
            } header: {
                Text("Look")
            } footer: {
                Text("The background changes every open shelf as you drag; thumbnails and text always stay fully visible. A shelf's colour tints its grabber, selection and drop targets; change one shelf's colour from its chevron menu.")
                    .settingsFootnote()
            }

            Section {
                Toggle(isOn: $keepAfterDragOut) {
                    Text("Keep items on the shelf after dragging them out")
                    Text("Otherwise dragged items leave the shelf, and an empty shelf closes. Hold Shift as you drop to keep them just once.")
                }
            } header: {
                Text("Dragging out")
            } footer: {
                Text("Pinned shelves always keep their items. Push a shelf against the left or right screen edge to tuck it away.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 400)
    }
}

// MARK: - Favourites

@MainActor
private struct FavouritesSettings: View {
    @State private var favourites = Prefs.favourites
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                ItemList(items: favourites, selection: $selection, empty: "No favourites yet") { path in
                    PathRow(path: path)
                }
                ListButtons(canRemove: selection != nil, remove: removeSelected) {
                    Button("Add Folder…") { add(apps: false) }
                    Button("Add App…") { add(apps: true) }
                }
            } header: {
                Text("Folders and apps")
            } footer: {
                Text("While you drag over a shelf, favourites appear as drop targets: folders get a copy (hold ⌘ to move), apps open the files. They're also under Copy To, Move To and Open With in the shelf menu.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 360)
    }

    private func add(apps: Bool) {
        guard let paths = choose(apps: apps) else { return }
        set(favourites + paths)
    }

    private func removeSelected() {
        guard let selection else { return }
        set(favourites.filter { $0 != selection })
        self.selection = nil
    }

    private func set(_ list: [String]) {
        var seen = Set<String>()
        favourites = list.filter { seen.insert($0).inserted }
        Prefs.favourites = favourites
    }
}

// MARK: - Automatic

@MainActor
private struct AutomaticSettings: View {
    @State private var screenshots = Prefs.screenshotsToShelf
    @State private var watched = Prefs.watchedFolders
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $screenshots) {
                    Text("Put new screenshots on a shelf")
                    Text("Screenshots are saved to \(ScreenshotDetector.screenshotFolder.lastPathComponent). Change that in the Screenshot app's Options.")
                }
            } header: {
                Text("Screenshots")
            }

            Section {
                ItemList(items: watched, selection: $selection, empty: "No watched folders") { path in
                    PathRow(path: path)
                }
                ListButtons(canRemove: selection != nil, remove: removeSelected) {
                    Button("Watch a Folder…") {
                        if let paths = choose(apps: false) { set(watched + paths) }
                    }
                }
            } header: {
                Text("Watched folders")
            } footer: {
                Text("New files in these folders (Downloads, for example) appear on a shelf in the top-right corner without interrupting you. Unfinished downloads are ignored.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 420)
        .onChange(of: screenshots) { _, on in
            Prefs.screenshotsToShelf = on
            AppModel.shared.reloadFolderWatchers()
        }
    }

    private func removeSelected() {
        guard let selection else { return }
        set(watched.filter { $0 != selection })
        self.selection = nil
    }

    private func set(_ list: [String]) {
        var seen = Set<String>()
        watched = list.filter { seen.insert($0).inserted }
        Prefs.watchedFolders = watched
        AppModel.shared.reloadFolderWatchers()
    }
}

// MARK: - About

@MainActor
private struct AboutSettings: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "–"
        let build = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text("Hoverbox")
                .font(.system(size: 20, weight: .bold))
            Text(version)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("A free, open-source drag-and-drop shelf.\nNo permissions, no network, no telemetry.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text("Copyright © 2026 Aswin Ravichandran. MIT License.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: 520, height: 300)
    }
}

// MARK: - Pieces

/// A selectable list for a settings section, or a quiet placeholder when it's empty.
@MainActor
private struct ItemList<Row: View>: View {
    let items: [String]
    @Binding var selection: String?
    let empty: String
    @ViewBuilder let row: (String) -> Row

    var body: some View {
        if items.isEmpty {
            Text(empty)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 60)
        } else {
            List(items, id: \.self, selection: $selection) { item in
                row(item).padding(.vertical, 2)
            }
            .frame(height: 140)
        }
    }
}

/// The ＋ / − buttons under a list. ＋ opens a menu of ways to add.
@MainActor
private struct ListButtons<AddMenu: View>: View {
    let canRemove: Bool
    let remove: () -> Void
    @ViewBuilder let addMenu: () -> AddMenu

    var body: some View {
        HStack(spacing: 0) {
            Menu { addMenu() } label: {
                Image(systemName: "plus").frame(width: 22, height: 18)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Add")
            .accessibilityLabel("Add")
            Divider().frame(height: 16)
            Button(action: remove) {
                Image(systemName: "minus").frame(width: 22, height: 18)
            }
            .disabled(!canRemove)
            .help("Remove the selected item")
            .accessibilityLabel("Remove")
            Spacer()
        }
        .buttonStyle(.borderless)
    }
}

/// Icon, name and location of a folder or app.
private struct PathRow: View {
    let path: String

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 0) {
                Text(FileManager.default.displayName(atPath: path))
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

/// Icon and name of an app, looked up from its bundle ID.
private struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack(spacing: 8) {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed").frame(width: 20, height: 20)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
                if url != nil {
                    Text(bundleID).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Asks for folders, or for apps in /Applications.
@MainActor
private func choose(apps: Bool) -> [String]? {
    let panel = NSOpenPanel()
    panel.allowsMultipleSelection = true
    panel.canChooseDirectories = !apps
    panel.canChooseFiles = apps
    if apps {
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
    }
    panel.prompt = apps ? "Add" : "Choose"
    guard panel.runModal() == .OK else { return nil }
    return panel.urls.map(\.path)
}

private extension Text {
    func settingsFootnote() -> some View {
        font(.system(size: 11)).foregroundStyle(.secondary)
    }
}
