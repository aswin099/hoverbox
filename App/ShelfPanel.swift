import AppKit
import Quartz

/// Floating, non-activating window for one shelf: it appears over every app
/// and Space without taking focus from the app you're dragging from.
final class ShelfPanel: NSPanel {
    /// The pile with its name: what a shelf looks like when it appears.
    static let compactSize = NSSize(width: 216, height: 236)
    /// Every item laid out, after clicking the name.
    static let expandedSize = NSSize(width: 452, height: 372)

    weak var controller: ShelfController?

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.compactSize),
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
        let size = frame.size
        let origin = NSPoint(x: point.x - size.width / 2, y: point.y - size.height / 2)
        setFrameOrigin(Self.clamp(NSRect(origin: origin, size: size), to: bounds).origin)
    }

    /// Puts the shelf back with its top-left corner at a saved spot, if that spot is still on a screen.
    func place(topLeft: NSPoint) -> Bool {
        let rect = NSRect(x: topLeft.x, y: topLeft.y - frame.height, width: frame.width, height: frame.height)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(rect) }) else { return false }
        setFrameOrigin(Self.clamp(rect, to: screen.visibleFrame).origin)
        return true
    }

    /// Grows or shrinks around the top edge's center, staying on screen.
    func resize(to size: NSSize, animated: Bool) {
        let old = frame
        var rect = NSRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height)
        if let bounds = screen?.visibleFrame { rect = Self.clamp(rect, to: bounds) }
        guard animated else {
            setFrame(rect, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.28
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            animator().setFrame(rect, display: true)
        }
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
