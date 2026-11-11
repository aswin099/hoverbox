import AppKit
import HoverboxCore
import KeyboardShortcuts

/// App-wide state: the open shelves, recently closed ones, the drag watcher,
/// the hotkey and the folder watchers.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var shelves: [ShelfController] = []
    @Published var isShakePaused = false

    @Published private(set) var recent = RecentShelves()
    /// Uploads, newest first, for the menu bar (last 30).
    @Published private(set) var uploads: [UploadRecord] = []

    private let watcher = DragWatcher()
    private let archive = ShelfArchive(fileURL: AppPaths.archive)
    private let recentArchive = ShelfArchive(fileURL: AppPaths.recentArchive, pinnedOnly: false)
    private var folderWatchers: [FolderWatcher] = []
    /// The shelf each watched source last filled, so a burst of new files lands on one shelf.
    private var watchedShelves: [String: ShelfController] = [:]
    private var started = false
    private var gestures = HotkeyGestures()
    /// The shelf used last: updated when one gains focus or the switcher lands on it.
    /// Tracked here because a window's key status lags just after it changes.
    private weak var focusedShelf: ShelfController?
    /// What was last dragged out of a shelf, for the long-press gesture to bring back.
    private var lastDraggedOut: [ShelfItem] = []
    private var defaultsObserver: NSObjectProtocol?
    private var appliedAppearance = Prefs.appearance

    func start() {
        guard !started else { return }
        started = true
        Prefs.register()

        let saved = archive.load()
        recent = RecentShelves(shelves: recentArchive.load())
        uploads = (try? Data(contentsOf: AppPaths.uploadHistory))
            .flatMap { try? JSONDecoder().decode([UploadRecord].self, from: $0) } ?? []
        AppPaths.removeUnusedDrops(keeping: saved + recent.shelves)
        for (index, shelf) in saved.enumerated() {
            let controller = ShelfController(shelf: shelf, model: self)
            shelves.append(controller)
            controller.refreshFiles()
            controller.showRestored(index: index)
        }

        watcher.rules = { [weak self] in Prefs.shakeRules(paused: self?.isShakePaused ?? false) }
        watcher.sensitivity = { Prefs.shakeSensitivity }
        watcher.trigger = { Prefs.openTrigger }
        watcher.dwellDelay = { Prefs.dwellDelay }
        watcher.onShake = { [weak self] point in self?.newShelf(at: point) }
        watcher.start()

        KeyboardShortcuts.onKeyDown(for: .newShelf) { [weak self] in
            self?.gestures.keyDown(at: ProcessInfo.processInfo.systemUptime)
        }
        KeyboardShortcuts.onKeyUp(for: .newShelf) { [weak self] in
            guard let self else { return }
            handle(gestures.keyUp(at: ProcessInfo.processInfo.systemUptime))
        }
        KeyboardShortcuts.onKeyUp(for: .nextShelf) { [weak self] in self?.focusNextShelf() }
        let actions: [(KeyboardShortcuts.Name, (ShelfController) -> Void)] = [
            (.actionZip, { $0.zip($0.actionTargets.compactMap(\.fileURL)) }),
            (.actionText, { $0.extractText($0.actionTargets.compactMap(\.fileURL).filter(TextRecognizer.canRead)) }),
            (.actionCompress, { $0.compress($0.actionTargets.compactMap(\.fileURL).filter(ImageTool.isImage)) }),
            (.actionResize, { $0.resize($0.actionTargets.compactMap(\.fileURL).filter(ImageTool.isImage), to: .percent(50)) }),
            (.actionAirDrop, { $0.airDrop($0.actionTargets) }),
            (.actionShare, { $0.share($0.actionTargets) }),
        ]
        for (name, perform) in actions {
            KeyboardShortcuts.onKeyUp(for: name) { [weak self] in
                guard let shelf = self?.activeShelf else { return }
                perform(shelf)
            }
        }
        // Appearance changes in Settings apply to open shelves straight away.
        defaultsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification,
                                                                  object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.applyAppearanceIfChanged()
                self?.writeStatusIfActionsChanged()
            }
        }
        reloadFolderWatchers()
        // Commands from the hoverbox command-line tool. Only local processes can post these.
        commandObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name(AppCommand.notificationName), object: nil, queue: .main
        ) { [weak self] note in
            guard let text = note.object as? String, let command = AppCommand(encoded: text) else { return }
            MainActor.assumeIsolated { self?.perform(command) }
        }
        writeStatus()
    }

    // MARK: Command-line tool

    private var commandObserver: NSObjectProtocol?

    /// The shelf a command means: its number from `hoverbox list`, else the newest.
    private func shelf(number: Int?) -> ShelfController? {
        guard let number else { return shelves.last }
        return shelves.indices.contains(number - 1) ? shelves[number - 1] : nil
    }

    func perform(_ command: AppCommand) {
        func files(_ paths: [String]) -> [ShelfItem] {
            paths.filter { FileManager.default.fileExists(atPath: $0) }.map { .file(URL(fileURLWithPath: $0)) }
        }
        switch command {
        case .newShelf(let paths):
            newShelf(at: placementPoint(near: NSEvent.mouseLocation), items: files(paths))
        case .add(let paths, let number):
            if let target = shelf(number: number) {
                target.add(files(paths))
                target.undockIfNeeded()
                target.panel.orderFrontRegardless()
            } else if number == nil {
                newShelf(at: placementPoint(near: NSEvent.mouseLocation), items: files(paths))
            }
        case .runAction(let name, let number):
            guard let target = shelf(number: number) else { return }
            if !target.performAction(named: name, onWholeShelf: true) {
                target.showStatus("No action called \(name)", isError: true)
            }
        case .close(let number):
            if let target = shelf(number: number) { close(target) }
        }
    }

    private var publishedActionNames: [String] = []

    private func writeStatusIfActionsChanged() {
        if Prefs.customActions.map(\.name) != publishedActionNames { writeStatus() }
    }

    /// Files from the Shortcuts app: a new shelf, or the newest one.
    func addFromShortcut(_ items: [ShelfItem], newShelf makeNew: Bool) {
        if !makeNew, let target = shelves.last {
            target.add(items)
            target.undockIfNeeded()
            target.panel.orderFrontRegardless()
        } else {
            newShelf(at: placementPoint(near: NSEvent.mouseLocation), items: items)
        }
    }

    /// What `hoverbox list`, `paths` and `actions` read.
    func writeStatus() {
        let infos = shelves.enumerated().map { AppStatus.ShelfInfo(number: $0.offset + 1, shelf: $0.element.shelf) }
        publishedActionNames = Prefs.customActions.map(\.name)
        let actions = publishedActionNames + ShelfController.builtInActionNames
        try? AppStatus(shelves: infos, actions: actions).save()
    }

    // MARK: Shortcuts

    private func handle(_ gesture: HotkeyGestures.Gesture) {
        switch gesture {
        case .newShelf:
            newShelf(at: placementPoint(near: NSEvent.mouseLocation))
        case .pasteIntoNewShelf:
            // The first press already opened a shelf; the second fills it from the clipboard.
            (shelves.last ?? newShelf(at: placementPoint(near: NSEvent.mouseLocation))).paste()
        case .recallDraggedOut:
            let items = lastDraggedOut.map { $0.refreshed() }.filter { !$0.isMissing }.map(\.item)
            if items.isEmpty {
                Announcer.say("Nothing to bring back")
                NSSound.beep()
            } else {
                newShelf(at: placementPoint(near: NSEvent.mouseLocation), items: items)
            }
        }
    }

    func rememberDraggedOut(_ items: [ShelfItem]) {
        if !items.isEmpty { lastDraggedOut = items }
    }

    /// The shelf the action shortcuts work on: the one used last, else the newest.
    var activeShelf: ShelfController? {
        shelves.first { $0 === focusedShelf } ?? shelves.last
    }

    func shelfGainedFocus(_ controller: ShelfController) {
        focusedShelf = controller
    }

    /// Cycles through open shelves, bringing each forward (and out of its dock).
    func focusNextShelf() {
        guard !shelves.isEmpty else {
            NSSound.beep()
            return
        }
        let current = shelves.firstIndex { $0 === focusedShelf }
        let next = shelves[current.map { ($0 + 1) % shelves.count } ?? 0]
        focusedShelf = next
        next.undockIfNeeded()
        next.bringToFront()
        Announcer.say("Shelf: \(next.shelf.title)")
    }

    /// Where a shelf opened by the shortcut or Finder goes (Settings › Shelves).
    func placementPoint(near pointer: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        guard let bounds = screen?.visibleFrame else { return pointer }
        let size = ShelfPanel.compactSize
        switch Prefs.placement {
        case .pointer: return pointer
        case .center: return NSPoint(x: bounds.midX, y: bounds.midY)
        case .topRight: return NSPoint(x: bounds.maxX - size.width / 2 - 12, y: bounds.maxY - size.height / 2 - 12)
        }
    }

    private func applyAppearanceIfChanged() {
        let appearance = Prefs.appearance
        guard appearance != appliedAppearance else { return }
        appliedAppearance = appearance
        shelves.forEach { $0.panel.appearance = appearance.nsAppearance }
    }

    @discardableResult
    func newShelf(at point: NSPoint, items: [ShelfItem] = []) -> ShelfController {
        // In copy mode the files go through add(), which copies them first.
        let copying = Prefs.keepCopies && items.contains { $0.fileURL != nil }
        let controller = ShelfController(shelf: Shelf(items: copying ? [] : items, color: Prefs.newShelfColor), model: self)
        shelves.append(controller)
        controller.show(centeredOn: point)
        if copying { controller.add(items) }
        Announcer.say(items.isEmpty ? "Shelf opened. Drop files on it, or press Command V to paste."
                                    : "Shelf opened with \(Shelf.summary(of: items))")
        if Prefs.openExpanded, !items.isEmpty { controller.setExpanded(true) }
        writeStatus()
        return controller
    }

    /// Files sent from Finder's "Add to Hoverbox": a new shelf at the pointer, or the shelf
    /// the previous batch went to if it arrived a moment ago (promised files arrive one by one).
    func addFromService(_ items: [ShelfItem]) {
        if let last = serviceShelf, Date().timeIntervalSince(serviceShelfTime) < 1.5, shelves.contains(where: { $0 === last }) {
            last.add(items)
        } else {
            serviceShelf = newShelf(at: placementPoint(near: NSEvent.mouseLocation), items: items)
        }
        serviceShelfTime = Date()
    }

    private weak var serviceShelf: ShelfController?
    private var serviceShelfTime = Date.distantPast

    func close(_ controller: ShelfController) {
        controller.panel.orderOut(nil)
        shelves.removeAll { $0 === controller }
        Announcer.say(controller.shelf.isEmpty ? "Shelf closed" : "Shelf closed. Reopen it from Recently Closed in the menu bar.")
        recent.remember(controller.shelf)
        saveRecent()
        removeUnusedDrops()
        save()
        writeStatus()
    }

    // MARK: Uploads

    func rememberUploads(_ records: [UploadRecord]) {
        uploads = Array((records.reversed() + uploads).prefix(30))
        saveUploads()
    }

    func forgetUploads() {
        uploads = []
        saveUploads()
    }

    /// Deletes an uploaded file from the server, then from the history.
    func deleteUpload(_ record: UploadRecord) {
        guard let destination = Prefs.uploadDestinations.first(where: { $0.id == record.destinationID }) else {
            uploads.removeAll { $0.id == record.id }
            saveUploads()
            return
        }
        Task.detached {
            let result = Result { try Uploader.delete(record, from: destination) }
            await MainActor.run {
                switch result {
                case .success:
                    self.uploads.removeAll { $0.id == record.id }
                    self.saveUploads()
                    Announcer.say("Deleted \(record.fileName) from \(destination.name)")
                case .failure(let error):
                    let alert = NSAlert(error: error)
                    alert.messageText = "Couldn't delete \(record.fileName)"
                    alert.informativeText = error.localizedDescription
                    NSApp.activate(ignoringOtherApps: true)
                    alert.runModal()
                }
            }
        }
    }

    private func saveUploads() {
        guard let data = try? JSONEncoder().encode(uploads) else { return }
        try? FileManager.default.createDirectory(at: AppPaths.support, withIntermediateDirectories: true)
        try? data.write(to: AppPaths.uploadHistory, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: AppPaths.uploadHistory.path)
    }

    // MARK: Recently closed

    /// Opens a recently closed shelf again, below the menu bar icon or at `point`.
    func reopen(_ id: UUID, at point: NSPoint) {
        guard let shelf = recent.take(id) else { return }
        saveRecent()
        let controller = ShelfController(shelf: shelf, model: self)
        shelves.append(controller)
        controller.refreshFiles()
        controller.show(centeredOn: point)
        save()
    }

    func clearRecent() {
        recent.clear()
        saveRecent()
        removeUnusedDrops()
    }

    /// Keeps files that open shelves, Recently Closed or the long-press gesture still need.
    private func removeUnusedDrops() {
        AppPaths.removeUnusedDrops(keeping: shelves.map(\.shelf) + recent.shelves + [Shelf(items: lastDraggedOut)])
    }

    private func saveRecent() {
        try? recentArchive.save(recent.shelves)
    }

    // MARK: Watched folders and screenshots

    /// Starts watching the folders chosen in Settings, and the screenshot folder if that's on.
    func reloadFolderWatchers() {
        folderWatchers.forEach { $0.stop() }
        folderWatchers = []
        for path in Prefs.watchedFolders {
            let folder = URL(fileURLWithPath: path, isDirectory: true)
            if let watcher = FolderWatcher(folder: folder, onNewItems: { [weak self] urls in
                self?.deliver(urls, from: "folder:" + path, name: folder.lastPathComponent)
            }) {
                folderWatchers.append(watcher)
            }
        }
        if Prefs.screenshotsToShelf, let watcher = FolderWatcher(folder: ScreenshotDetector.screenshotFolder,
                                                                filter: ScreenshotDetector.isScreenshot,
                                                                onNewItems: { [weak self] urls in
                                                                    self?.deliver(urls, from: "screenshots", name: "Screenshots")
                                                                }) {
            folderWatchers.append(watcher)
        }
    }

    /// Puts new files on the shelf this source filled last (if it's still open), or on a new
    /// named shelf in the top-right corner. Never takes focus from what you're doing.
    private func deliver(_ urls: [URL], from source: String, name: String) {
        if let shelf = watchedShelves[source], shelves.contains(where: { $0 === shelf }) {
            shelf.add(urls.map(ShelfItem.file))
            Announcer.say("\(Shelf.summary(of: urls.map(ShelfItem.file))) added to \(name)")
            shelf.undockIfNeeded()
            shelf.panel.orderFrontRegardless()
            return
        }
        let bounds = NSScreen.main?.visibleFrame ?? .zero
        let size = ShelfPanel.compactSize
        let offset = CGFloat(watchedShelves.count % 4) * 28
        let controller = newShelf(at: NSPoint(x: bounds.maxX - size.width / 2 - 12 - offset,
                                              y: bounds.maxY - size.height / 2 - 12 - offset),
                                  items: urls.map(ShelfItem.file))
        controller.rename(to: name)
        watchedShelves[source] = controller
    }

    func closeUnpinnedShelves() {
        for controller in shelves where !controller.shelf.isPinned {
            close(controller)
        }
    }

    func shelfChanged(_ controller: ShelfController) {
        objectWillChange.send()
        writeStatus()
        save()
    }

    private func save() {
        try? archive.save(shelves.map(\.shelf))
    }

    /// `hoverbox://new` opens an empty shelf at the pointer; `path=`, `link=` and `text=` fill it.
    /// `hoverbox://share?…` is what the Share extension sends.
    /// `hoverbox://add?path=/a&path=/b` adds files to the newest shelf, or a new one.
    func handle(url: URL) {
        guard url.scheme == "hoverbox", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let query = components.queryItems ?? []
        let items = query.compactMap { entry -> ShelfItem? in
            guard let value = entry.value, !value.isEmpty else { return nil }
            switch entry.name {
            case "path": return .file(URL(fileURLWithPath: (value as NSString).expandingTildeInPath))
            case "link": return URL(string: value).map(ShelfItem.link)
            case "text": return .text(value)
            default: return nil
            }
        }
        switch components.host {
        case "new":
            newShelf(at: NSEvent.mouseLocation, items: items)
        case "share":
            // From the Share extension: like Finder's Add to Hoverbox.
            addFromService(items)
        case "add":
            if let target = shelves.last {
                target.add(items)
                target.bringToFront()
            } else {
                newShelf(at: NSEvent.mouseLocation, items: items)
            }
        #if DEBUG
        case "debug":
            debugCommand(components)
        #endif
        default:
            break
        }
    }

    #if DEBUG
    /// Development aid: `hoverbox://debug?expand=1&layout=list&snapshot=/dir` sets the newest
    /// shelf's state and writes a PNG of every shelf window into the folder (`name=` names the newest one).
    private func debugCommand(_ components: URLComponents) {
        let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }) { $1 }
        if let folder = query["windows"] {
            let lines = NSApp.windows.map { window in
                "\(type(of: window)) visible=\(window.isVisible) onScreen=\(window.occlusionState.contains(.visible)) "
                    + "frame=\(Int(window.frame.minX)),\(Int(window.frame.minY)) \(Int(window.frame.width))x\(Int(window.frame.height))"
            }
            try? lines.joined(separator: "\n").write(toFile: folder + "/windows.txt", atomically: true, encoding: .utf8)
            for (index, window) in NSApp.windows.enumerated() {
                guard let view = window.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: folder + "/window-\(index).png"))
            }
            return
        }
        if let tab = query["settings"].flatMap(Int.init), let folder = query["snapshot"] {
            let window = SettingsWindow.make()
            (window.contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = tab
            window.orderFront(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // The frame view includes the toolbar tabs.
                if let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    let url = URL(fileURLWithPath: folder).appendingPathComponent("settings-\(tab).png")
                    try? rep.representation(using: .png, properties: [:])?.write(to: url)
                }
                window.close()
            }
            return
        }
        // Test the shortcut gestures through the real handler, without pressing keys.
        if let paste = query["testPaste"] {
            let pasteboard = NSPasteboard(name: NSPasteboard.Name("hoverbox-debug"))
            pasteboard.clearContents()
            pasteboard.setString(paste, forType: .string)
            ShelfController.pasteboard = pasteboard
        }
        if let path = query["remember"] { rememberDraggedOut([.file(URL(fileURLWithPath: path))]) }
        if let gesture = query["gesture"] {
            let now = ProcessInfo.processInfo.systemUptime
            func press(at time: TimeInterval, holding: TimeInterval = 0.08) {
                gestures.keyDown(at: time)
                handle(gestures.keyUp(at: time + holding))
            }
            switch gesture {
            case "short": press(at: now)
            case "double":
                press(at: now)
                press(at: now + 0.25)
            case "long": press(at: now, holding: 0.7)
            default: break
            }
        }
        // Several ⌥⇧Tab presses in a row, logged as "pressed -> focused shelf (key shelf)". Run from
        // one command because each hoverbox:// link activates the app and moves key status itself.
        if let log = query["nextLog"], let count = Int(query["next"] ?? "") {
            for press in 0..<count {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(press) * 0.5 + 0.5) { [self] in
                    focusNextShelf()
                    let focused = shelves.firstIndex { $0 === focusedShelf } ?? -1
                    let key = shelves.firstIndex { $0.panel.isKeyWindow } ?? -1
                    let line = "press \(press + 1) -> \(focused + 1) (key \(key + 1))\n"
                    let old = (try? String(contentsOfFile: log, encoding: .utf8)) ?? ""
                    try? (old + line).write(toFile: log, atomically: true, encoding: .utf8)
                }
            }
        }
        // Temporary upload destinations for testing against a local server.
        if let kind = query["testDest"], let endpoint = query["endpoint"] {
            let destination = kind == "webdav"
                ? UploadDestination(name: "Test WebDAV", kind: .webDAV(WebDAVSettings(folderURL: endpoint, username: "tester")))
                : UploadDestination(name: "Test S3", kind: .s3(S3Settings(endpoint: endpoint, region: "us-east-1", bucket: "testbucket",
                                                                           accessKeyID: "TESTKEY", prefix: "hb")),
                                    linkLifetime: 3600)
            Prefs.uploadDestinations = Prefs.uploadDestinations.filter { !$0.name.hasPrefix("Test ") } + [destination]
            UploadSecrets.setSecret(kind == "webdav" ? "test-password" : "test/secret+key", for: destination.id)
            UserDefaults.standard.set(destination.id.uuidString, forKey: Prefs.defaultDestinationKey)
        }
        if query["clearTestDests"] == "1" {
            Prefs.uploadDestinations.filter { $0.name.hasPrefix("Test ") }.forEach { UploadSecrets.setSecret("", for: $0.id) }
            Prefs.uploadDestinations = Prefs.uploadDestinations.filter { !$0.name.hasPrefix("Test ") }
            UserDefaults.standard.removeObject(forKey: Prefs.defaultDestinationKey)
            uploads.removeAll()
            saveUploads()
        }
        if let log = query["testConnection"], let destination = Prefs.defaultDestination {
            Task.detached {
                let result = Result { try Uploader.test(destination) }
                let text: String
                switch result {
                case .success: text = "ok"
                case .failure(let error): text = "failed: \(error.localizedDescription)"
                }
                try? text.write(toFile: log, atomically: true, encoding: .utf8)
            }
        }
        if let log = query["deleteLastUpload"], let record = uploads.first {
            deleteUpload(record)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [self] in
                try? "remaining=\(uploads.count)".write(toFile: log, atomically: true, encoding: .utf8)
            }
        }
        guard let shelf = shelves.last else { return }
        let files = (components.queryItems ?? []).filter { $0.name == "path" }.compactMap { $0.value.map { URL(fileURLWithPath: $0) } }
        if let folder = query["favDrop"] { shelf.drop(files.map(ShelfItem.file), on: Favourite(url: URL(fileURLWithPath: folder))) }
        if let folder = query["favMove"] { shelf.copy(files, into: URL(fileURLWithPath: folder), move: true) }
        if let expand = query["expand"] { shelf.setExpanded(expand == "1") }
        if let layout = query["layout"].flatMap(ShelfLayout.init(rawValue:)) { shelf.setLayout(layout) }
        if let target = query["target"] { shelf.isDropTargeted = target == "1" }
        if let count = query["select"].flatMap(Int.init) { shelf.selection = Set(shelf.shelf.items.prefix(count).map(\.id)) }
        if let color = query["color"] { shelf.setColor(ShelfColor(rawValue: color)) }
        if let dock = query["dock"] {
            if dock == "off" { shelf.undock() } else if let screen = shelf.panel.screen ?? NSScreen.main {
                shelf.dock(dock == "left" ? .left : .right, on: screen)
            }
        }
        if query["close"] == "1" { close(shelf) }
        guard let folder = query["snapshot"] else { return }
        let wait = Double(query["delay"] ?? "") ?? 1.0
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [self] in
            for (index, controller) in shelves.enumerated() {
                guard let view = controller.panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = query["name"].map { index == shelves.count - 1 ? $0 : "\($0)-\(index)" } ?? "shelf-\(index)"
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
                let first = controller.shelf.items.first?.fileURL?.path ?? "-"
                let state = "title=\(controller.shelf.title) items=\(controller.shelf.items.count) first=\(first) key=\(controller.panel.isKeyWindow) focused=\(controller === self.focusedShelf) status=\(controller.status?.text ?? "-") expanded=\(controller.isExpanded) "
                    + "docked=\(String(describing: controller.dockedEdge)) window=\(Int(controller.panel.frame.width))x\(Int(controller.panel.frame.height)) "
                    + "x=\(Int(controller.panel.frame.minX)) shelves=\(shelves.count) recent=\(self.recent.shelves.count)\n"
                try? state.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    #endif
}
