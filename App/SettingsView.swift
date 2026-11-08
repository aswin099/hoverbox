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
    /// Every tab has this size, so the window stays still when you switch tabs.
    static let size = CGSize(width: 720, height: 500)

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
        add("Opening", "hand.draw", ShakeSettings())
        add("Shortcuts", "keyboard", ShortcutSettings())
        add("Shelves", "square.stack", ShelvesSettings())
        add("Actions", "wand.and.stars", ActionsSettings())
        add("Uploads", "icloud.and.arrow.up", UploadsSettings())
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
    @State private var installMessage: String?

    private static let candidates = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin"]

    private var installedAt: String? {
        Self.candidates.map { $0 + "/hoverbox" }.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// Links `hoverbox` into the first folder on the usual PATH that can be written without an
    /// administrator password, pointing at the tool inside this copy of the app.
    private func installCommand() {
        let tool = Bundle.main.bundleURL.appendingPathComponent("Contents/SharedSupport/bin/hoverbox")
        let fileManager = FileManager.default
        guard fileManager.isExecutableFile(atPath: tool.path) else {
            installMessage = "The tool is missing from this copy of Hoverbox."
            return
        }
        for folder in Self.candidates {
            if folder.hasSuffix(".local/bin") { try? fileManager.createDirectory(atPath: folder, withIntermediateDirectories: true) }
            guard fileManager.isWritableFile(atPath: folder) else { continue }
            let link = folder + "/hoverbox"
            try? fileManager.removeItem(atPath: link)
            do {
                try fileManager.createSymbolicLink(atPath: link, withDestinationPath: tool.path)
                installMessage = folder.hasSuffix(".local/bin")
                    ? "Installed at \(link). If Terminal can't find it, add ~/.local/bin to your PATH."
                    : "Installed at \(link). Open a new Terminal window and try hoverbox help."
                return
            } catch {
                continue
            }
        }
        installMessage = "Couldn't install. In Terminal, run: sudo ln -s \"\(tool.path)\" /usr/local/bin/hoverbox"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("hoverbox command") {
                    Button(installedAt == nil ? "Install…" : "Reinstall") { installCommand() }
                }
                if let message = installMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                }
            } header: {
                Text("Command-line tool")
            } footer: {
                Text("Lets Terminal, scripts and coding agents open shelves, add files, list them and run actions. Try hoverbox help.")
                    .settingsFootnote()
            }

            Section("Startup") {
                Toggle("Open Hoverbox at login", isOn: $launchAtLogin)
            }

            Section {
                LabeledContent("Permissions") {
                    Label("None needed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                LabeledContent("Network") {
                    Label("Only when you upload", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
            } header: {
                Text("Privacy")
            } footer: {
                Text("Shelves hold references to your files, not copies. Nothing leaves your Mac unless you share, AirDrop or upload it, and uploads only go to storage you set up in Settings › Uploads.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
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
    @AppStorage(Prefs.openTriggerKey) private var trigger = OpenTrigger.shake.rawValue
    @AppStorage(Prefs.dwellDelayKey) private var dwellDelay = 1.0
    @State private var excluded = Prefs.excludedBundleIDs
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $shakeEnabled) {
                    Text("Open a shelf while dragging")
                    Text("Works in every app and needs no permissions. The shortcut, the menu bar icon and Finder's Add to Hoverbox always work too.")
                }
                Picker("Open by", selection: $trigger) {
                    Text("Shaking the pointer").tag(OpenTrigger.shake.rawValue)
                    Text("Holding the pointer still").tag(OpenTrigger.dwell.rawValue)
                    Text("Either").tag(OpenTrigger.both.rawValue)
                }
                .disabled(!shakeEnabled)
                if trigger != OpenTrigger.dwell.rawValue {
                    Picker("Shake sensitivity", selection: $sensitivity) {
                        Text("Low: big, deliberate shakes").tag(ShakeDetector.Sensitivity.low.rawValue)
                        Text("Medium").tag(ShakeDetector.Sensitivity.medium.rawValue)
                        Text("High: small shakes are enough").tag(ShakeDetector.Sensitivity.high.rawValue)
                    }
                    .disabled(!shakeEnabled)
                }
                if trigger != OpenTrigger.shake.rawValue {
                    Picker("Hold still for", selection: $dwellDelay) {
                        Text("Half a second").tag(0.5)
                        Text("1 second").tag(1.0)
                        Text("1.5 seconds").tag(1.5)
                        Text("2 seconds").tag(2.0)
                    }
                    .disabled(!shakeEnabled)
                }
            } footer: {
                Text("Holding still suits head pointers, dwell control and tremors, where shaking is hard or happens by accident. It never triggers over a shelf you're dropping onto.")
                    .settingsFootnote()
            }

            Section {
                ItemList(items: excluded, selection: $selection, empty: "Shelves open in every app") { bundleID in
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
                Text("Don't open shelves while dragging in")
            } footer: {
                Text("Useful for games and design tools where you drag a lot.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
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

// MARK: - Shortcuts

@MainActor
private struct ShortcutSettings: View {
    var body: some View {
        Form {
            Section {
                KeyboardShortcuts.Recorder("New shelf", name: .newShelf)
                KeyboardShortcuts.Recorder("Switch between shelves", name: .nextShelf)
            } header: {
                Text("Shelves")
            } footer: {
                Text("Press New shelf twice quickly to put the clipboard on the new shelf. Hold it down to bring back what you last dragged out. In Finder, ⇧⌘B adds the selected files (change it in System Settings › Keyboard › Keyboard Shortcuts › Services).")
                    .settingsFootnote()
            }

            Section {
                KeyboardShortcuts.Recorder("Compress to ZIP", name: .actionZip)
                KeyboardShortcuts.Recorder("Extract text", name: .actionText)
                KeyboardShortcuts.Recorder("Compress images", name: .actionCompress)
                KeyboardShortcuts.Recorder("Resize images to 50%", name: .actionResize)
                KeyboardShortcuts.Recorder("AirDrop", name: .actionAirDrop)
                KeyboardShortcuts.Recorder("Share", name: .actionShare)
            } header: {
                Text("Actions")
            } footer: {
                Text("These work on the shelf you used last: its selected items, or everything on it. None are set until you choose keys.")
                    .settingsFootnote()
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
    }
}

// MARK: - Shelves

@MainActor
private struct ShelvesSettings: View {
    @AppStorage(Prefs.backgroundOpacity) private var backgroundOpacity = Prefs.defaultBackgroundOpacity
    @AppStorage(Prefs.newShelfColorKey) private var newShelfColor = ""
    @AppStorage(Prefs.keepAfterDragOut) private var keepAfterDragOut = false
    @AppStorage(Prefs.keepCopiesKey) private var keepCopies = false
    @AppStorage(Prefs.placementKey) private var placement = ShelfPlacement.pointer.rawValue
    @AppStorage(Prefs.appearanceKey) private var appearance = ShelfAppearance.system.rawValue
    @AppStorage(Prefs.largeShelvesKey) private var largeShelves = false
    @AppStorage(Prefs.openExpandedKey) private var openExpanded = false

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
                Picker("Appearance", selection: $appearance) {
                    Text("Match the system").tag(ShelfAppearance.system.rawValue)
                    Text("Light").tag(ShelfAppearance.light.rawValue)
                    Text("Dark").tag(ShelfAppearance.dark.rawValue)
                }
                Picker("Size when showing all items", selection: $largeShelves) {
                    Text("Regular").tag(false)
                    Text("Large").tag(true)
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
                Picker("Shortcut and Finder shelves open", selection: $placement) {
                    Text("At the pointer").tag(ShelfPlacement.pointer.rawValue)
                    Text("In the top-right corner").tag(ShelfPlacement.topRight.rawValue)
                    Text("In the middle of the screen").tag(ShelfPlacement.center.rawValue)
                }
                Toggle("Show all items when a shelf opens with files", isOn: $openExpanded)
                Toggle(isOn: $keepCopies) {
                    Text("Keep copies, not the original files")
                    Text("Files you add are copied into Hoverbox, so the originals are never moved or changed. Copies are instant on the same disk; they are deleted once the shelf is closed and gone from Recently Closed.")
                }
            } header: {
                Text("Adding files")
            } footer: {
                Text("Shelves opened by shaking or holding still always appear at the pointer, where your drag is.")
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
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
    }
}

// MARK: - Actions

@MainActor
private struct ActionsSettings: View {
    @State private var actions = Prefs.customActions
    @State private var selection: UUID?

    private static let examples: [CustomAction] = [
        CustomAction(name: "Web Images", steps: [.resizeLongestSide(1600), .convert(.jpeg), .compress]),
        CustomAction(name: "Email Bundle", steps: [.compress, .zip]),
        CustomAction(name: "Count Words", steps: [.script(#"cat "$@" | wc -w | tr -d ' '"#)]),
    ]

    private var selectedIndex: Int? { actions.firstIndex { $0.id == selection } }

    var body: some View {
        Form {
            Section {
                if actions.isEmpty {
                    Text("No actions yet. Add one, or start from an example.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    List(actions, selection: $selection) { action in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(action.name)
                            Text(action.steps.map(\.summary).joined(separator: " → "))
                                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 110)
                }
                ListButtons(canRemove: selection != nil, remove: removeSelected) {
                    Button("New Action") { add(CustomAction(name: "New Action", steps: [])) }
                    Divider()
                    ForEach(Self.examples) { example in
                        Button("Example: \(example.name)") { add(CustomAction(name: example.name, steps: example.steps)) }
                    }
                }
            } header: {
                Text("Your actions")
            } footer: {
                Text("Run them from a shelf's chevron menu, from Terminal with hoverbox run NAME, or from the Shortcuts app. They make new files; originals are never changed.")
                    .settingsFootnote()
            }

            if let index = selectedIndex {
                Section {
                    TextField("Name", text: $actions[index].name)
                    ForEach(actions[index].steps.indices, id: \.self) { step in
                        StepRow(step: $actions[index].steps[step],
                                moveUp: step > 0 ? { actions[index].steps.swapAt(step, step - 1) } : nil,
                                remove: { actions[index].steps.remove(at: step) })
                    }
                    Menu("Add Step") {
                        Button("Resize images to a longest side") { actions[index].steps.append(.resizeLongestSide(1600)) }
                        Button("Resize images by percent") { actions[index].steps.append(.resizePercent(50)) }
                        Button("Convert images") { actions[index].steps.append(.convert(.jpeg)) }
                        Button("Compress images") { actions[index].steps.append(.compress) }
                        Button("Compress to ZIP") { actions[index].steps.append(.zip) }
                        Divider()
                        Button("Run a shell script") { actions[index].steps.append(.script(#"for file in "$@"; do echo "$file"; done"#)) }
                    }
                    .fixedSize()
                } header: {
                    Text("Steps")
                } footer: {
                    Text("Each step works on what the step before it made. Scripts run in zsh with the files as $@; write new files into $HOVERBOX_OUTPUT, and anything printed is added to the shelf as text. Scripts stop after 2 minutes.")
                        .settingsFootnote()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
        .onChange(of: actions) { _, list in Prefs.customActions = list }
    }

    private func add(_ action: CustomAction) {
        var action = action
        var name = action.name, number = 2
        while actions.contains(where: { $0.name == name }) {
            name = "\(action.name) \(number)"
            number += 1
        }
        action.name = name
        actions.append(action)
        selection = action.id
    }

    private func removeSelected() {
        actions.removeAll { $0.id == selection }
        selection = nil
    }
}

/// One step of an action, with its own controls.
private struct StepRow: View {
    @Binding var step: CustomAction.Step
    let moveUp: (() -> Void)?
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top) {
            content
            Spacer(minLength: 8)
            if let moveUp {
                Button(action: moveUp) { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).help("Move up").accessibilityLabel("Move step up")
            }
            Button(action: remove) { Image(systemName: "trash") }
                .buttonStyle(.borderless).help("Remove step").accessibilityLabel("Remove step")
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .resizeLongestSide(let side):
            Stepper(value: Binding(get: { side }, set: { step = .resizeLongestSide(max(16, $0)) }), in: 16...10000, step: 100) {
                Text("Resize images: longest side \(side) px")
            }
        case .resizePercent(let percent):
            Picker("Resize images by", selection: Binding(get: { percent }, set: { step = .resizePercent($0) })) {
                ForEach([25, 50, 75], id: \.self) { Text("\($0)%").tag($0) }
            }
        case .convert(let format):
            Picker("Convert images to", selection: Binding(get: { format }, set: { step = .convert($0) })) {
                ForEach(ImageFormat.writable, id: \.self) { Text($0.displayName).tag($0) }
            }
        case .compress:
            Text("Compress images (keeps only smaller files)")
        case .zip:
            Text("Compress everything to one ZIP")
        case .script(let script):
            VStack(alignment: .leading, spacing: 4) {
                Text("Run shell script")
                TextEditor(text: Binding(get: { script }, set: { step = .script($0) }))
                    .font(.system(size: 12, design: .monospaced))
                    .frame(height: 70)
                    .accessibilityLabel("Script")
            }
        }
    }
}

private extension CustomAction.Step {
    var summary: String {
        switch self {
        case .resizeLongestSide(let side): return "Resize \(side) px"
        case .resizePercent(let percent): return "Resize \(percent)%"
        case .convert(let format): return format.displayName
        case .compress: return "Compress"
        case .zip: return "ZIP"
        case .script: return "Script"
        }
    }
}

// MARK: - Uploads

@MainActor
private struct UploadsSettings: View {
    @State private var destinations = Prefs.uploadDestinations
    @State private var selection: UUID?
    @AppStorage(Prefs.defaultDestinationKey) private var defaultID = ""
    @State private var secret = ""
    @State private var testResult: (ok: Bool, text: String)?
    @State private var testing = false

    private var index: Int? { destinations.firstIndex { $0.id == selection } }
    private var defaultDestinationID: UUID? { Prefs.defaultDestination?.id }

    var body: some View {
        Form {
            Section {
                if destinations.isEmpty {
                    Text("Nowhere to upload to yet. Add your own storage to get Upload & Copy Link.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 50)
                } else {
                    List(destinations, selection: $selection) { destination in
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(destination.name)
                                Text(destination.kind.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if destination.id == defaultDestinationID && destinations.count > 1 {
                                Text("Default").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .frame(height: 100)
                }
                ListButtons(canRemove: selection != nil, remove: removeSelected) {
                    Button("Amazon S3") {
                        add("Amazon S3", .s3(S3Settings(endpoint: "https://s3.us-east-1.amazonaws.com", region: "us-east-1", bucket: "", accessKeyID: "")))
                    }
                    Button("Cloudflare R2") {
                        add("Cloudflare R2", .s3(S3Settings(endpoint: "https://ACCOUNT-ID.r2.cloudflarestorage.com", region: "auto", bucket: "", accessKeyID: "")))
                    }
                    Button("Backblaze B2") {
                        add("Backblaze B2", .s3(S3Settings(endpoint: "https://s3.us-west-004.backblazeb2.com", region: "us-west-004", bucket: "", accessKeyID: "")))
                    }
                    Button("Other S3-compatible (MinIO, Wasabi…)") {
                        add("My Storage", .s3(S3Settings(endpoint: "https://", region: "us-east-1", bucket: "", accessKeyID: "")))
                    }
                    Divider()
                    Button("WebDAV (Nextcloud, NAS…)") {
                        add("WebDAV", .webDAV(WebDAVSettings(folderURL: "https://", username: "")))
                    }
                }
            } header: {
                Text("Where uploads go")
            } footer: {
                Text("Hoverbox only goes online when you upload, and only to the storage listed here. Keys and passwords are kept in your Keychain.")
                    .settingsFootnote()
            }

            if let index {
                Section {
                    TextField("Name", text: $destinations[index].name)
                    switch destinations[index].kind {
                    case .s3:
                        let s3 = s3Binding(index)
                        TextField("Endpoint", text: s3.endpoint, prompt: Text("https://s3.example.com"))
                        TextField("Region", text: s3.region, prompt: Text("us-east-1, or auto for R2"))
                        TextField("Bucket", text: s3.bucket)
                        TextField("Folder in the bucket", text: s3.prefix, prompt: Text("Optional"))
                        TextField("Access key ID", text: s3.accessKeyID)
                        SecureField("Secret access key", text: $secret)
                        TextField("Public address", text: s3.publicBaseURL, prompt: Text("Optional, for public buckets or a custom domain"))
                        if s3.wrappedValue.publicBaseURL.isEmpty {
                            Picker("Links work for", selection: $destinations[index].linkLifetime) {
                                Text("1 hour").tag(3600.0)
                                Text("1 day").tag(86_400.0)
                                Text("7 days (the most S3 allows)").tag(604_800.0)
                            }
                        }
                    case .webDAV:
                        let dav = webDAVBinding(index)
                        TextField("Folder address", text: dav.folderURL, prompt: Text("https://cloud.example.com/remote.php/dav/files/me/Shared"))
                        TextField("Username", text: dav.username)
                        SecureField("Password", text: $secret)
                        TextField("Public address", text: dav.publicBaseURL, prompt: Text("Optional, where the files can be read from"))
                    }
                    HStack {
                        Button(testing ? "Testing…" : "Test Connection") { test(destinations[index]) }
                            .disabled(testing)
                        if destinations.count > 1 && destinations[index].id != defaultDestinationID {
                            Button("Use as Default") { defaultID = destinations[index].id.uuidString }
                        }
                        Spacer()
                    }
                    if let testResult {
                        Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(testResult.ok ? Color.green : Color.orange)
                            .font(.callout)
                    }
                } header: {
                    Text("Settings")
                } footer: {
                    Text("Test Connection uploads a tiny text file and deletes it again. Private buckets get links that stop working after the time above; public buckets get permanent links.")
                        .settingsFootnote()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
        .onChange(of: destinations) { _, list in Prefs.uploadDestinations = list }
        .onChange(of: selection) { _, id in
            secret = id.flatMap(UploadSecrets.secret(for:)) ?? ""
            testResult = nil
        }
        .onChange(of: secret) { _, value in
            if let id = selection { UploadSecrets.setSecret(value, for: id) }
        }
    }

    private func s3Binding(_ index: Int) -> Binding<S3Settings> {
        Binding(get: {
            if case .s3(let settings) = destinations[index].kind { return settings }
            return S3Settings(endpoint: "", region: "", bucket: "", accessKeyID: "")
        }, set: { destinations[index].kind = .s3($0) })
    }

    private func webDAVBinding(_ index: Int) -> Binding<WebDAVSettings> {
        Binding(get: {
            if case .webDAV(let settings) = destinations[index].kind { return settings }
            return WebDAVSettings(folderURL: "", username: "")
        }, set: { destinations[index].kind = .webDAV($0) })
    }

    private func add(_ name: String, _ kind: UploadDestination.Kind) {
        let destination = UploadDestination(name: name, kind: kind)
        destinations.append(destination)
        selection = destination.id
    }

    private func removeSelected() {
        guard let id = selection else { return }
        UploadSecrets.setSecret("", for: id)
        destinations.removeAll { $0.id == id }
        selection = nil
    }

    private func test(_ destination: UploadDestination) {
        testing = true
        testResult = nil
        Task.detached {
            let result = Result { try Uploader.test(destination) }
            await MainActor.run {
                testing = false
                switch result {
                case .success: testResult = (true, "Connected: uploaded and removed a test file.")
                case .failure(let error): testResult = (false, error.localizedDescription)
                }
            }
        }
    }
}

private extension UploadDestination.Kind {
    var summary: String {
        switch self {
        case .s3(let settings):
            let host = URL(string: settings.endpoint)?.host ?? settings.endpoint
            return settings.bucket.isEmpty ? host : "\(settings.bucket) on \(host)"
        case .webDAV(let settings):
            return URL(string: settings.folderURL)?.host ?? "WebDAV"
        }
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
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
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
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
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
        return "Version \(short)"
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
            Text("A free, open-source drag-and-drop shelf.\nNo permissions, no telemetry, online only to upload.")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
            Text("Copyright © 2026 Aswin Ravichandran. MIT License.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(32)
        .frame(width: SettingsWindow.size.width, height: SettingsWindow.size.height)
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
