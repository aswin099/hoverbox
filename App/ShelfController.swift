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
    /// Where a reorder drag would land, as an index into the items; nil when not reordering.
    @Published private(set) var reorderIndex: Int?
    /// Row frames reported by ShelfView, in its top-left-origin coordinate space.
    var rowFrames: [UUID: CGRect] = [:]
    /// A short message in the footer ("3 images resized"); errors show in orange.
    @Published private(set) var status: (text: String, isError: Bool)?
    /// The drop-strip target (an Instant Action or a favourite) under the pointer during a drag.
    @Published var hoveredZone: String?
    /// Compact shows the pile and its name; expanded lays out every item.
    @Published private(set) var isExpanded = false
    @Published private(set) var layout = ShelfLayout.saved
    /// The screen edge the shelf is tucked against as a slim tab, if any.
    @Published private(set) var dockedEdge: DockEdge?
    private var statusClear: DispatchWorkItem?
    private var shrinkWindow: DispatchWorkItem?

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

        let catcher = DropCatcherView(frame: NSRect(origin: .zero, size: ShelfPanel.compactSize))
        catcher.onDrop = { [weak self] items in self?.add(items) }
        catcher.onTargetChange = { [weak self] targeted in
            self?.isDropTargeted = targeted
            // Dragging something over a docked tab brings the shelf out to catch it.
            if targeted { self?.undockIfNeeded() }
        }
        catcher.onReorderHover = { [weak self] point in
            guard let self else { return }
            let index = point.map { self.insertionIndex(at: $0) }
            if index != reorderIndex { reorderIndex = index }
        }
        catcher.onReorderDrop = { [weak self] ids, point in
            guard let self else { return }
            move(ids, to: insertionIndex(at: point))
        }
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
        if let origin = shelf.origin, panel.place(topLeft: NSPoint(x: origin.x, y: origin.y)) {
            panel.orderFrontRegardless()
            return
        }
        let bounds = NSScreen.main?.visibleFrame ?? .zero
        let offset = CGFloat(index) * 24
        let size = ShelfPanel.compactSize
        show(centeredOn: NSPoint(x: bounds.maxX - size.width / 2 - 24 - offset,
                                 y: bounds.maxY - size.height / 2 - 24 - offset))
    }

    func bringToFront() {
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    @objc private func panelMoved() {
        shelf.origin = .init(x: panel.frame.minX, y: panel.frame.maxY)
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
        if shelf.isEmpty && isExpanded { setExpanded(false) }
        changed()
    }

    /// Growing: the window takes its full size first (the transparent margin hides that),
    /// then the card animates open inside it. Shrinking: the card animates closed first,
    /// then the window shrinks to match. The window itself never animates.
    func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded, !(expanded && shelf.isEmpty) else { return }
        shrinkWindow?.cancel()
        if expanded {
            panel.resize(to: ShelfPanel.expandedSize)
            // Lay out and draw at the new window size first, so the card starts exactly where
            // it was on screen; then animate it open on the next pass.
            panel.contentView?.layoutSubtreeIfNeeded()
            panel.displayIfNeeded()
            DispatchQueue.main.async { [weak self] in
                guard let self, !shelf.isEmpty else { return }
                isExpanded = true
                panel.makeKey()
            }
        } else {
            isExpanded = false
            let shrink = DispatchWorkItem { [weak self] in
                guard let self, !isExpanded else { return }
                panel.resize(to: ShelfPanel.compactSize)
            }
            shrinkWindow = shrink
            let delay = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : ShelfView.cardAnimationDuration
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: shrink)
        }
    }

    func setLayout(_ newLayout: ShelfLayout) {
        layout = newLayout
        ShelfLayout.saved = newLayout
    }

    func move(_ ids: [UUID], to index: Int) {
        let before = shelf.items.map(\.id)
        shelf.move(ids, to: index)
        if shelf.items.map(\.id) != before { changed() }
    }

    /// The position under a point in the drop view (bottom-left origin): before the first
    /// item the point is above, or, in the grid, left of within the same row.
    private func insertionIndex(at point: NSPoint) -> Int {
        // Into the card's coordinates: top-left origin, inside the shadow margin.
        let x = point.x - ShelfPanel.margin
        let y = (panel.contentView?.bounds.height ?? 0) - point.y - ShelfPanel.margin
        for (index, item) in shelf.items.enumerated() {
            guard let frame = rowFrames[item.id] else { continue }
            if layout == .list ? y < frame.midY : (y < frame.minY || (y <= frame.maxY && x < frame.midX)) {
                return index
            }
        }
        return shelf.items.count
    }

    /// Asks for a shelf name; an empty name goes back to the automatic one.
    func promptForName() {
        let alert = NSAlert()
        alert.messageText = "Name This Shelf"
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: shelf.name ?? "")
        field.placeholderString = shelf.title
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { rename(to: field.stringValue) }
    }

    /// Renames a file on disk after asking for the new name, and keeps it on the shelf.
    func rename(_ item: ShelfItem) {
        guard let url = item.fileURL else { return }
        let alert = NSAlert()
        alert.messageText = "Rename “\(url.lastPathComponent)”"
        alert.informativeText = "This renames the file itself, wherever it is."
        alert.addButton(withTitle: "Rename")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(string: url.lastPathComponent)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        // Select the name without its extension, like Finder does.
        DispatchQueue.main.async {
            let stem = (url.lastPathComponent as NSString).deletingPathExtension
            field.currentEditor()?.selectedRange = NSRange(location: 0, length: (stem as NSString).length)
        }
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), name != url.lastPathComponent else { return }
        let destination = url.deletingLastPathComponent().appendingPathComponent(name)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            shelf.updateFile(item.id, to: destination)
            changed()
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func togglePin() {
        shelf.isPinned.toggle()
        shelf.origin = .init(x: panel.frame.minX, y: panel.frame.maxY)
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

    /// Shows a footer message; it clears after a few seconds unless `sticky` (used while work runs).
    func showStatus(_ text: String, isError: Bool = false, sticky: Bool = false) {
        statusClear?.cancel()
        status = (text, isError)
        guard !sticky else { return }
        let clear = DispatchWorkItem { [weak self] in self?.status = nil }
        statusClear = clear
        DispatchQueue.main.asyncAfter(deadline: .now() + (isError ? 6 : 4), execute: clear)
    }

    // MARK: Colour

    func setColor(_ color: ShelfColor?) {
        shelf.color = color
        changed()
    }

    // MARK: Docking

    /// Called when the user lets go after moving the shelf. Pushing its card past the left
    /// or right edge of the screen tucks it away as a slim tab.
    func windowDragEnded() {
        guard NSEvent.pressedMouseButtons & 1 == 0 else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in self?.windowDragEnded() }
            return
        }
        guard dockedEdge == nil, let screen = panel.screen ?? NSScreen.main else { return }
        let card = panel.frame.insetBy(dx: ShelfPanel.margin, dy: ShelfPanel.margin)
        if card.minX <= screen.frame.minX + 2 {
            dock(.left, on: screen)
        } else if card.maxX >= screen.frame.maxX - 2 {
            dock(.right, on: screen)
        }
    }

    func dock(_ edge: DockEdge, on screen: NSScreen) {
        if isExpanded {
            shrinkWindow?.cancel()
            isExpanded = false
        }
        let size = ShelfPanel.tabSize
        let bounds = screen.visibleFrame
        let x = edge == .left ? screen.frame.minX : screen.frame.maxX - size.width
        let y = min(max(panel.frame.midY - size.height / 2, bounds.minY), bounds.maxY - size.height)
        dockedEdge = edge
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func undock() {
        guard let edge = dockedEdge, let screen = panel.screen ?? NSScreen.main else { return }
        let size = ShelfPanel.compactSize
        let bounds = screen.visibleFrame
        let x = edge == .left ? bounds.minX + 4 : bounds.maxX - size.width - 4
        let y = min(max(panel.frame.midY - size.height / 2, bounds.minY), bounds.maxY - size.height)
        dockedEdge = nil
        panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
    }

    func undockIfNeeded() {
        if dockedEdge != nil { undock() }
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
    func didDragOut(ids: [UUID], operation: NSDragOperation, at screenPoint: NSPoint) {
        // Ending over this shelf means a reorder (handled on drop), not a drag out.
        guard !operation.isEmpty, !panel.frame.contains(screenPoint) else { return }
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
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem("Open") { [weak self] in targets.forEach { self?.open($0) } })
        if targets.contains(where: { $0.fileURL != nil }) {
            menu.addItem(ActionMenuItem("Quick Look") { [weak self] in
                self?.selection = Set(targets.map(\.id))
                self?.toggleQuickLook()
            })
            menu.addItem(ActionMenuItem("Show in Finder") { [weak self] in self?.reveal(targets) })
        }
        if targets.count == 1, item.fileURL != nil, !missing.contains(item.id) {
            menu.addItem(ActionMenuItem("Rename…") { [weak self] in self?.rename(item) })
        }
        menu.addItem(ActionMenuItem("Copy") { [weak self] in self?.copyToPasteboard(targets) })
        menu.addItem(.separator())
        let actions = actionsMenu(for: targets.filter { !missing.contains($0.id) })
        for action in actions.items {
            actions.removeItem(action)
            menu.addItem(action)
        }
        menu.addItem(.separator())
        menu.addItem(ActionMenuItem(targets.count > 1 ? "Remove \(targets.count) Items" : "Remove from Shelf") { [weak self] in
            self?.remove(Set(targets.map(\.id)))
        })
        return menu
    }

    // MARK: Keyboard

    /// Space previews, Delete removes, ⌘A selects all, Esc clears the selection,
    /// arrows move the selection (Shift extends it), Return opens.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        switch event.keyCode {
        case 49:
            toggleQuickLook()
            return true
        case 125, 126:
            moveSelection(by: event.keyCode == 125 ? 1 : -1, extending: flags.contains(.shift))
            return true
        case 36, 76:
            if !selection.isEmpty { shelf.items(in: selection).prefix(10).forEach { open($0) } }
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

    private func moveSelection(by step: Int, extending: Bool) {
        guard !shelf.items.isEmpty else { return }
        let current = lastClicked.flatMap { id in shelf.items.firstIndex { $0.id == id } }
        let next = current.map { min(max(0, $0 + step), shelf.items.count - 1) } ?? (step > 0 ? 0 : shelf.items.count - 1)
        let id = shelf.items[next].id
        if extending { selection.insert(id) } else { selection = [id] }
        lastClicked = id
        if QLPreviewPanel.sharedPreviewPanelExists(), QLPreviewPanel.shared().isVisible {
            QLPreviewPanel.shared().reloadData()
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
