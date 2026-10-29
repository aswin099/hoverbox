import AppKit
import HoverboxCore
import KeyboardShortcuts

/// App-wide state: the open shelves, the drag watcher and the hotkey.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var shelves: [ShelfController] = []
    @Published var isShakePaused = false

    private let watcher = DragWatcher()
    private let archive = ShelfArchive(fileURL: AppPaths.archive)
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        Prefs.register()

        let saved = archive.load()
        AppPaths.removeUnusedDrops(keeping: saved)
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
    }

    @discardableResult
    func newShelf(at point: NSPoint, items: [ShelfItem] = []) -> ShelfController {
        let controller = ShelfController(shelf: Shelf(items: items), model: self)
        shelves.append(controller)
        controller.show(centeredOn: point)
        return controller
    }

    func close(_ controller: ShelfController) {
        controller.panel.orderOut(nil)
        shelves.removeAll { $0 === controller }
        AppPaths.removeUnusedDrops(keeping: shelves.map(\.shelf))
        save()
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
        guard let folder = query["snapshot"] else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [shelves] in
            for (index, controller) in shelves.enumerated() {
                guard let view = controller.panel.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: rep)
                let name = query["name"].map { index == shelves.count - 1 ? $0 : "\($0)-\(index)" } ?? "shelf-\(index)"
                let url = URL(fileURLWithPath: folder).appendingPathComponent(name + ".png")
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
        }
    }
    #endif
}
