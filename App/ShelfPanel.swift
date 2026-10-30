import AppKit
import Quartz
import SwiftUI

/// Floating, non-activating window for one shelf: it appears over every app
/// and Space without taking focus from the app you're dragging from.
final class ShelfPanel: NSPanel {
    /// The visible card: the pile with its name, as a shelf first appears.
    static let compactCard = NSSize(width: 216, height: 236)
    /// The visible card with every item laid out, after clicking the name (Settings › Shelves › Size).
    static var expandedCard: NSSize {
        Prefs.largeShelves ? NSSize(width: 600, height: 480) : NSSize(width: 452, height: 372)
    }
    /// Clear space around the card for its shadow. The card draws its own shadow,
    /// so it stays smooth while the card animates.
    static let margin: CGFloat = 22

    static let compactSize = window(for: compactCard)
    /// A shelf tucked against a screen edge.
    static let tabSize = NSSize(width: 34, height: 120)
    static var expandedSize: NSSize { window(for: expandedCard) }

    static func window(for card: NSSize) -> NSSize {
        NSSize(width: card.width + margin * 2, height: card.height + margin * 2)
    }

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
        hasShadow = false
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

    /// Changes the window size in one step around the top edge's center, staying on
    /// screen. The card inside does the animating; the window never resizes frame by frame.
    func resize(to size: NSSize) {
        let old = frame
        var rect = NSRect(x: old.midX - size.width / 2, y: old.maxY - size.height, width: size.width, height: size.height)
        if let bounds = screen?.visibleFrame { rect = Self.clamp(rect, to: bounds) }
        setFrame(rect, display: true)
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

/// Lets the user move the shelf by dragging any empty part of the card. The card is
/// almost all controls and thumbnails, so the window background alone isn't enough.
struct WindowDragHandle: NSViewRepresentable {
    var onDoubleClick: () -> Void = {}
    var onDragEnded: () -> Void = {}

    func makeNSView(context: Context) -> WindowDragHandleView { WindowDragHandleView() }

    func updateNSView(_ view: WindowDragHandleView, context: Context) {
        view.onDoubleClick = onDoubleClick
        view.onDragEnded = onDragEnded
    }
}

final class WindowDragHandleView: NSView {
    var onDoubleClick: () -> Void = {}
    var onDragEnded: () -> Void = {}

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick()
        } else {
            window?.performDrag(with: event)
            DispatchQueue.main.async { [weak self] in self?.onDragEnded() }
        }
    }
}

enum DockEdge {
    case left, right
}

/// The shelf's see-through background: macOS's own behind-window blur, with how much of it
/// shows controlled by the Glass–Solid setting. SwiftUI's materials carry a fixed tint that
/// stays nearly opaque, so they can't go as clear as "glass" should.
struct ShelfBackground: NSViewRepresentable {
    /// 0 is clear glass, 1 is solid.
    var solidity: Double

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.autoresizingMask = [.width, .height]
        container.addSubview(blur)
        let tint = NSView()
        tint.wantsLayer = true
        tint.autoresizingMask = [.width, .height]
        container.addSubview(tint)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        guard container.subviews.count == 2 else { return }
        let blur = container.subviews[0], tint = container.subviews[1]
        blur.frame = container.bounds
        tint.frame = container.bounds
        // Glass keeps a faint blur so text stays readable; solid ends at the plain window colour.
        blur.alphaValue = 0.45 + 0.55 * solidity
        container.effectiveAppearance.performAsCurrentDrawingAppearance {
            tint.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(solidity * 0.92).cgColor
        }
    }
}
