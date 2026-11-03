import AppIntents
import HoverboxCore

// Actions for Apple's Shortcuts app (and Spotlight / Siri): put files on a shelf, get the
// files on a shelf, and run an action on one.

struct AddToShelfIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Hoverbox"
    static var description = IntentDescription("Puts files on a new Hoverbox shelf, or on the newest one.")

    @Parameter(title: "Files")
    var files: [IntentFile]

    @Parameter(title: "New Shelf", default: true)
    var newShelf: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$files) to Hoverbox") { \.$newShelf }
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        AppModel.shared.addFromShortcut(Self.items(from: files), newShelf: newShelf)
        return .result()
    }

    /// Files Shortcuts hands over by location stay where they are, like any shelf item. Ones that
    /// only exist as data, or as a temporary copy Shortcuts will delete, are kept in Drops.
    @MainActor
    static func items(from files: [IntentFile]) -> [ShelfItem] {
        let folder = AppPaths.newDropFolder()
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().path
        return files.compactMap { file in
            if let url = file.fileURL, FileManager.default.fileExists(atPath: url.path),
               !url.resolvingSymlinksInPath().path.hasPrefix(temporary) {
                return .file(url)
            }
            let name = file.filename.isEmpty ? "Shared File" : file.filename
            let target = OutputNaming.url(in: folder, for: name, fileExtension: (name as NSString).pathExtension)
            return (try? file.data.write(to: target)) == nil ? nil : .file(target)
        }
    }
}

struct GetShelfFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Hoverbox Files"
    static var description = IntentDescription("Gets the files on the Hoverbox shelf you used last.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> {
        AppModel.shared.start()
        let urls = AppModel.shared.activeShelf?.shelf.items.compactMap(\.fileURL) ?? []
        return .result(value: urls.map { IntentFile(fileURL: $0) })
    }
}

struct RunShelfActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Run Hoverbox Action"
    static var description = IntentDescription("Runs one of your actions, or a built-in one, on everything on the Hoverbox shelf you used last.")

    @Parameter(title: "Action", optionsProvider: ActionNameOptions())
    var action: String

    static var parameterSummary: some ParameterSummary {
        Summary("Run \(\.$action) on the Hoverbox shelf")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.start()
        guard let shelf = AppModel.shared.activeShelf else {
            throw HoverboxIntentError.message("No Hoverbox shelf is open.")
        }
        guard shelf.performAction(named: action, onWholeShelf: true) else {
            throw HoverboxIntentError.message("There's no Hoverbox action called \(action).")
        }
        return .result()
    }
}

struct ActionNameOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        Prefs.customActions.map(\.name) + ShelfController.builtInActionNames
    }
}

enum HoverboxIntentError: Error, CustomLocalizedStringResourceConvertible {
    case message(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .message(let text): return LocalizedStringResource(stringLiteral: text)
        }
    }
}

struct HoverboxShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AddToShelfIntent(), phrases: ["Add to \(.applicationName)", "Put files on a \(.applicationName) shelf"],
                    shortTitle: "Add to Shelf", systemImageName: "tray.and.arrow.down")
        AppShortcut(intent: GetShelfFilesIntent(), phrases: ["Get files from \(.applicationName)"],
                    shortTitle: "Get Shelf Files", systemImageName: "square.stack")
        AppShortcut(intent: RunShelfActionIntent(), phrases: ["Run a \(.applicationName) action"],
                    shortTitle: "Run Action", systemImageName: "bolt")
    }
}
