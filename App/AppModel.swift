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
        watcher.onShake = { [weak self] point in self?.newShelf(at: point) }
        watcher.start()

        KeyboardShortcuts.onKeyUp(for: .newShelf) { [weak self] in
            self?.newShelf(at: NSEvent.mouseLocation)
        }
        reloadFolderWatchers()
    }

    @discardableResult
    func newShelf(at point: NSPoint, items: [ShelfItem] = []) -> ShelfController {
        let controller = ShelfController(shelf: Shelf(items: items, color: Prefs.newShelfColor), model: self)
        shelves.append(controller)
        controller.show(centeredOn: point)
        return controller
    }

    func close(_ controller: ShelfController) {
        controller.panel.orderOut(nil)
        shelves.removeAll { $0 === controller }
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

    /// `hoverbox://new` opens an empty shelf at the pointer.
    /// `hoverbox://add?path=/a&path=/b` adds files to the newest shelf, or a new one.
    func handle(url: URL) {
        guard url.scheme == "hoverbox", let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let paths = (components.queryItems ?? []).filter { $0.name == "path" }.compactMap(\.value)
        let items = paths.map { ShelfItem.file(URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath)) }
        switch components.host {
        case "new":
            newShelf(at: NSEvent.mouseLocation, items: items)
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
                let state = "title=\(controller.shelf.title) items=\(controller.shelf.items.count) expanded=\(controller.isExpanded) "
                    + "docked=\(String(describing: controller.dockedEdge)) window=\(Int(controller.panel.frame.width))x\(Int(controller.panel.frame.height)) "
                    + "x=\(Int(controller.panel.frame.minX)) shelves=\(shelves.count) recent=\(self.recent.shelves.count)\n"
                try? state.write(to: url.deletingPathExtension().appendingPathExtension("txt"), atomically: true, encoding: .utf8)
            }
        }
    }
    #endif
}
