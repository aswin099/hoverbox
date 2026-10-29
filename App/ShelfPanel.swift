import AppKit
import Quartz

/// Floating, non-activating window for one shelf: it appears over every app
/// and Space without taking focus from the app you're dragging from.
final class ShelfPanel: NSPanel {
    static let size = NSSize(width: 248, height: 320)

    weak var controller: ShelfController?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.size),
                   styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isMovableByWindowBackground = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { true }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) == true { return }
        super.keyDown(with: event)
    }

    /// Centers the shelf on `point`, kept inside that screen.
    func place(centeredOn point: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = NSPoint(x: point.x - Self.size.width / 2, y: point.y - Self.size.height / 2)
        setFrameOrigin(Self.clamp(NSRect(origin: origin, size: Self.size), to: bounds).origin)
    }

    /// Puts the shelf back at a saved origin if that spot is still on a screen.
    func place(at origin: NSPoint) -> Bool {
        let rect = NSRect(origin: origin, size: Self.size)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) else { return false }
        setFrameOrigin(Self.clamp(rect, to: screen.visibleFrame).origin)
        return true
    }

    private static func clamp(_ rect: NSRect, to bounds: NSRect) -> NSRect {
        var rect = rect
        rect.origin.x = min(max(rect.minX, bounds.minX + 8), bounds.maxX - rect.width - 8)
        rect.origin.y = min(max(rect.minY, bounds.minY + 8), bounds.maxY - rect.height - 8)
        return rect
    }

    // MARK: Quick Look

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = controller
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
    }
}
