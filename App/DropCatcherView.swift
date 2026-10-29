import AppKit
import HoverboxCore

/// The shelf's drop target. Plain AppKit so it takes every kind of drag:
/// file URLs, file promises (Photos, Mail, some browsers), images, links and
/// text. Being an ordinary drop target is also why shelves need no permission.
/// Drags that start on this same shelf reorder it instead of adding items.
final class DropCatcherView: NSView {
    var onDrop: (([ShelfItem]) -> Void)?
    var onTargetChange: ((Bool) -> Void)?
    /// Called while reordering with the pointer in this view's coordinates (nil when it leaves).
    var onReorderHover: ((NSPoint?) -> Void)?
    var onReorderDrop: (([UUID], NSPoint) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(DropReader.acceptedTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func reorderSource(_ sender: NSDraggingInfo) -> DragSourceView? {
        guard let source = sender.draggingSource as? DragSourceView, source.window === window else { return nil }
        return source
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        if reorderSource(sender) != nil {
            onReorderHover?(convert(sender.draggingLocation, from: nil))
            return .move
        }
        onTargetChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChange?(false)
        onReorderHover?(nil)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetChange?(false)
        onReorderHover?(nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChange?(false)
        onReorderHover?(nil)
        if let source = reorderSource(sender) {
            onReorderDrop?(source.draggedIDs, convert(sender.draggingLocation, from: nil))
            return true
        }
        return DropReader.read(sender.draggingPasteboard) { [weak self] items in self?.onDrop?(items) }
    }
}

/// Turns a dragging pasteboard into shelf items. Shared by shelves and the menu bar icon.
enum DropReader {
    static var acceptedTypes: [NSPasteboard.PasteboardType] {
        [.fileURL, .URL, .string, .tiff, .png]
            + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    }

    private static let promiseQueue = OperationQueue()

    /// Reads what was dropped and calls `deliver` on the main thread (later, for
    /// promised files). Returns false when there's nothing usable.
    static func read(_ pasteboard: NSPasteboard, deliver: @escaping ([ShelfItem]) -> Void) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            deliver(urls.map(ShelfItem.file))
            return true
        }
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: AppPaths.newDropFolder(), options: [:],
                                              operationQueue: promiseQueue) { url, error in
                    guard error == nil else { return }
                    DispatchQueue.main.async { deliver([.file(url)]) }
                }
            }
            return true
        }
        if pasteboard.availableType(from: [.tiff, .png]) != nil, let url = saveImage(from: pasteboard) {
            deliver([.file(url)])
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            deliver(urls.map(ShelfItem.link))
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                deliver([.link(url)])
            } else {
                deliver([.text(string)])
            }
            return true
        }
        return false
    }

    /// Writes dragged image data (for example from a browser) to a PNG in the Drops folder.
    private static func saveImage(from pasteboard: NSPasteboard) -> URL? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = AppPaths.newDropFolder().appendingPathComponent("Dropped Image.png")
        return (try? png.write(to: url)) != nil ? url : nil
    }
}
