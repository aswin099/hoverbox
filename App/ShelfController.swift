import AppKit
import HoverboxCore
import Quartz
import SwiftUI

/// Owns one shelf: its window, its items, selection, and what happens on
/// drop, drag-out, keys and Quick Look.
@MainActor
final class ShelfController: NSObject, ObservableObject, Identifiable {
    @Published private(set) var shelf: Shelf
    @Published var selection: Set<UUID> = []
    @Published private(set) var missing: Set<UUID> = []
    @Published var isDropTargeted = false

    let panel = ShelfPanel()
    private weak var model: AppModel?
    private var lastClicked: UUID?

    nonisolated var id: UUID { shelfID }
    private nonisolated let shelfID: UUID

    init(shelf: Shelf, model: AppModel) {
        self.shelf = shelf
        self.shelfID = shelf.id
        self.model = model
        super.init()

        let catcher = DropCatcherView(frame: NSRect(origin: .zero, size: ShelfPanel.size))
        catcher.onDrop = { [weak self] items in self?.add(items) }
        catcher.onTargetChange = { [weak self] targeted in self?.isDropTargeted = targeted }
        let host = NSHostingView(rootView: ShelfView(controller: self))
        host.frame = catcher.bounds
        host.autoresizingMask = [.width, .height]
        catcher.addSubview(host)
        panel.contentView = catcher
        panel.controller = self

        NotificationCenter.default.addObserver(self, selector: #selector(panelMoved),
                                               name: NSWindow.didMoveNotification, object: panel)
    }

    // MARK: Showing

    func show(centeredOn point: NSPoint) {
        panel.place(centeredOn: point)
        panel.orderFrontRegardless()
    }

    /// Shows a restored shelf where it was, or cascaded from the top-right if that screen is gone.
    func showRestored(index: Int) {
        if let origin = shelf.origin, panel.place(at: NSPoint(x: origin.x, y: origin.y)) {
            panel.orderFrontRegardless()
            return
        }
        let bounds = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(index) * 24
        show(centeredOn: NSPoint(x: bounds.maxX - ShelfPanel.size.width / 2 - 24 - offset,
                                 y: bounds.maxY - ShelfPanel.size.height / 2 - 24 - offset))
    }

    func bringToFront() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc private func panelMoved() {
        shelf.origin = .init(x: panel.frame.minX, y: panel.frame.minY)
        if shelf.isPinned { changed() }
    }

    // MARK: Editing

    func add(_ items: [ShelfItem]) {
        let added = shelf.add(items)
        guard !added.isEmpty else { return }
        changed()
    }

    func remove(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        shelf.remove(ids: ids)
        selection.subtract(ids)
        missing.subtract(ids)
        changed()
    }

    func move(_ id: UUID, to index: Int) {
        shelf.move(id, to: index)
        changed()
    }

    func togglePin() {
        shelf.isPinned.toggle()
        shelf.origin = .init(x: panel.frame.minX, y: panel.frame.minY)
        changed()
    }

    func rename(to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        shelf.name = trimmed.isEmpty ? nil : trimmed
        changed()
    }

    func close() {
        model?.close(self)
    }

    /// Follows moved or renamed files and flags the ones that are gone.
    func refreshFiles() {
        var gone: Set<UUID> = []
        var updated = shelf
        for (index, item) in shelf.items.enumerated() {
            let result = item.refreshed()
            updated.items[index] = result.item
            if result.isMissing { gone.insert(item.id) }
        }
        if updated != shelf {
            shelf = updated
            changed()
        }
        missing = gone
    }

    private func changed() {
        model?.shelfChanged(self)
    }

    // MARK: Selection and clicks

    /// What a drag starting on `id` carries: the whole selection if `id` is in it, otherwise just that item.
    func dragItems(startingWith id: UUID) -> [ShelfItem] {
        selection.contains(id) ? shelf.items(in: selection) : shelf.items.filter { $0.id == id }
    }

    func click(_ id: UUID, modifiers: NSEvent.ModifierFlags) {
        panel.makeKey()
        if modifiers.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else if modifiers.contains(.shift), let anchor = lastClicked,
                  let from = shelf.items.firstIndex(where: { $0.id == anchor }),
                  let to = shelf.items.firstIndex(where: { $0.id == id }) {
            selection = Set(shelf.items[min(from, to)...max(from, to)].map(\.id))
        } else {
            selection = [id]
        }
        lastClicked = id
    }

    func open(_ item: ShelfItem) {
        switch item.content {
        case .file(let url), .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let text):
            copyToPasteboard([.text(text)])
        }
    }

    func reveal(_ items: [ShelfItem]) {
        let urls = items.compactMap(\.fileURL)
        if !urls.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(urls) }
    }

    func copyToPasteboard(_ items: [ShelfItem]) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map(\.pasteboardWriter))
    }

    /// Called when a drag out of this shelf finishes. Dragged items leave the
    /// shelf unless it's pinned, the user chose to keep items, or Shift was held.
    func didDragOut(ids: [UUID], operation: NSDragOperation) {
        guard !operation.isEmpty else { return }
        if shelf.isPinned || Prefs.shouldKeepAfterDragOut || NSEvent.modifierFlags.contains(.shift) {
            refreshFiles()
            return
        }
        remove(Set(ids))
        if shelf.isEmpty { close() }
    }

    func menu(for item: ShelfItem) -> NSMenu {
        let targets = dragItems(startingWith: item.id)
        let menu = NSMenu()
        menu.addItem(ActionMenuItem("Open") { [weak self] in targets.forEach { self?.open($0) } })
        if targets.contains(where: { $0.fileURL != nil }) {
            menu.addItem(ActionMenuItem("Quick Look") { [weak self] in
                self?.selection = Set(targets.map(\.id))
                self?.toggleQuickLook()
            })
            menu.addItem(ActionMenuItem("Show in Finder") { [weak self] in self?.reveal(targets) })
        }
        menu.addItem(ActionMenuItem("Copy") { [weak self] in self?.copyToPasteboard(targets) })
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(targets.count > 1 ? "Remove \(targets.count) Items" : "Remove from Shelf") { [weak self] in
            self?.remove(Set(targets.map(\.id)))
        })
        return menu
    }

    // MARK: Keyboard

    /// Space previews, Delete removes, ⌘A selects all, Esc clears the selection.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 49:
            toggleQuickLook()
            return true
        case 51, 117:
            remove(selection)
            return true
        case 53:
            selection = []
            return true
        default:
            if flags == .command, event.charactersIgnoringModifiers == "a" {
                selection = Set(shelf.items.map(\.id))
                return true
            }
            return false
        }
    }

    // MARK: Quick Look

    fileprivate var previewURLs: [URL] {
        shelf.items(in: selection).compactMap(\.fileURL).filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func toggleQuickLook() {
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().orderOut(nil)
            return
        }
        guard !previewURLs.isEmpty else { return }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        let preview = QLPreviewPanel.shared()!
        preview.reloadData()
        preview.makeKeyAndOrderFront(nil)
    }
}

extension ShelfController: QLPreviewPanelDataSource {
    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { previewURLs.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { previewURLs[index] as NSURL }
    }
}
