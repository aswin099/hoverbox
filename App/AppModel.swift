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

    private let watcher = DragWatcher()
    private let archive = ShelfArchive(fileURL: AppPaths.archive)
    private let recentArchive = ShelfArchive(fileURL: AppPaths.recentArchive, pinnedOnly: false)
    private var folderWatchers: [FolderWatcher] = []
    /// The shelf each watched source last filled, so a burst of new files lands on one shelf.
    private var watchedShelves: [String: ShelfController] = [:]
    private var started = false
    private var gestures = HotkeyGestures()
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
            MainActor.assumeIsolated { self?.applyAppearanceIfChanged() }
        }
        reloadFolderWatchers()
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

    /// The shelf the action shortcuts work on: the one you're using, else the newest.
    var activeShelf: ShelfController? {
        shelves.first { $0.panel.isKeyWindow } ?? shelves.last
    }

    /// Cycles through open shelves, bringing each forward (and out of its dock).
    func focusNextShelf() {
        guard !shelves.isEmpty else {
            NSSound.beep()
            return
        }
        let current = shelves.firstIndex { $0.panel.isKeyWindow }
        let next = shelves[current.map { ($0 + 1) % shelves.count } ?? 0]
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
        AppPaths.removeUnusedDrops(keeping: shelves.map(\.shelf) + recent.shelves)
        save()
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
        AppPaths.removeUnusedDrops(keeping: shelves.map(\.shelf))
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
        guard let shelf = shelves.last else { return }
        if let expand = query["expand"] { shelf.setExpanded(expand == "1") }
        if let layout = query["layout"].flatMap(ShelfLayout.init(rawValue:)) { shelf.setLayout(layout) }
        if let target = query["target"] { shelf.isDropTargeted = target == "1" }
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
                let state = "title=\(controller.shelf.title) items=\(controller.shelf.items.count) first=\(first) status=\(controller.status?.text ?? "-") expanded=\(controller.isExpanded) "
                    + "docked=\(String(describing: controller.dockedEdge)) window=\(Int(controller.panel.frame.width))x\(Int(controller.panel.frame.height)) "
                    + "x=\(Int(controller.panel.frame.minX)) shelves=\(shelves.count) recent=\(self.recent.shelves.count)\n"
                try? state.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    #endif
}
