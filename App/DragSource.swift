import AppKit
import HoverboxCore
import SwiftUI

/// Makes a SwiftUI shelf tile draggable with AppKit's multi-item dragging,
/// which SwiftUI's `onDrag` can't do (it carries one item). It also handles
/// clicks, double-clicks and the right-click menu for the tile.
struct DragSource: NSViewRepresentable {
    var items: () -> [ShelfItem]
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var menu: () -> NSMenu? = { nil }
    var onEnded: ([UUID], NSDragOperation, NSPoint) -> Void

    func makeNSView(context: Context) -> DragSourceView { DragSourceView() }

    func updateNSView(_ view: DragSourceView, context: Context) {
        view.items = items
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        view.menuProvider = menu
        view.onEnded = onEnded
    }
}

final class DragSourceView: NSView, NSDraggingSource {
    var items: () -> [ShelfItem] = { [] }
    var onClick: (NSEvent.ModifierFlags) -> Void = { _ in }
    var onDoubleClick: () -> Void = {}
    var menuProvider: () -> NSMenu? = { nil }
    var onEnded: ([UUID], NSDragOperation, NSPoint) -> Void = { _, _, _ in }

    private var mouseDownEvent: NSEvent?
    private(set) var draggedIDs: [UUID] = []

    // Shelves are non-activating panels; take the first click instead of spending it on focus.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        if event.clickCount == 2 { onDoubleClick() }
    }

    override func mouseUp(with event: NSEvent) {
        if let down = mouseDownEvent, down.clickCount == 1 { onClick(event.modifierFlags) }
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let start = down.locationInWindow, now = event.locationInWindow
        guard hypot(now.x - start.x, now.y - start.y) > 3 else { return }
        mouseDownEvent = nil

        let list = items()
        guard !list.isEmpty else { return }
        draggedIDs = list.map(\.id)
        let origin = convert(start, from: nil)
        let draggingItems = list.enumerated().map { index, item in
            let draggingItem = NSDraggingItem(pasteboardWriter: item.pasteboardWriter)
            let offset = CGFloat(min(index, 4)) * 4
            draggingItem.setDraggingFrame(NSRect(x: origin.x - 24 + offset, y: origin.y - 24 - offset, width: 48, height: 48),
                                          contents: item.dragImage)
            return draggingItem
        }
        let session = beginDraggingSession(with: draggingItems, event: down, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .pile
    }

    override func menu(for event: NSEvent) -> NSMenu? { menuProvider() }

    func draggingSession(_ session: NSDraggingSession,
                         sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Allowing copy and move lets Finder apply its own keys: Option copies, Command moves.
        context == .outsideApplication ? [.copy, .move, .link, .generic] : [.copy, .generic]
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        onEnded(draggedIDs, operation, screenPoint)
        draggedIDs = []
    }
}

extension ShelfItem {
    var pasteboardWriter: NSPasteboardWriting {
        switch content {
        case .file(let url): return url as NSURL
        case .link(let url): return url as NSURL
        case .text(let text): return text as NSString
        }
    }

    var dragImage: NSImage {
        switch content {
        case .file(let url): return NSWorkspace.shared.icon(forFile: url.path)
        case .link: return NSImage(systemSymbolName: "link", accessibilityDescription: "Link") ?? NSImage()
        case .text: return NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Text") ?? NSImage()
        }
    }
}

/// An NSMenuItem that runs a closure, for building menus without target/action plumbing.
final class ActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
