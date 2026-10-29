import AppKit
import HoverboxCore

/// The shelf's drop target. Plain AppKit so it takes every kind of drag:
/// file URLs, file promises (Photos, Mail, some browsers), images, links and
/// text. Being an ordinary drop target is also why shelves need no permission.
final class DropCatcherView: NSView {
    var onDrop: (([ShelfItem]) -> Void)?
    var onTargetChange: ((Bool) -> Void)?
    private let promiseQueue = OperationQueue()

    override init(frame: NSRect) {
        super.init(frame: frame)
        let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png] + promiseTypes)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Dragging items out of this same shelf shouldn't drop them back in.
        if (sender.draggingSource as? NSView)?.window === window { return [] }
        onTargetChange?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChange?(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        onTargetChange?(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChange?(false)
        let pasteboard = sender.draggingPasteboard

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self],
                                             options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            onDrop?(urls.map(ShelfItem.file))
            return true
        }
        if let receivers = pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !receivers.isEmpty {
            for receiver in receivers {
                receiver.receivePromisedFiles(atDestination: AppPaths.newDropFolder(), options: [:],
                                              operationQueue: promiseQueue) { [weak self] url, error in
                    guard error == nil else { return }
                    DispatchQueue.main.async { self?.onDrop?([.file(url)]) }
                }
            }
            return true
        }
        if pasteboard.availableType(from: [.tiff, .png]) != nil, let url = saveImage(from: pasteboard) {
            onDrop?([.file(url)])
            return true
        }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty {
            onDrop?(urls.map(ShelfItem.link))
            return true
        }
        if let string = pasteboard.string(forType: .string) {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return false }
            if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                onDrop?([.link(url)])
            } else {
                onDrop?([.text(string)])
            }
            return true
        }
        return false
    }

    /// Writes dragged image data (for example from a browser) to a PNG in the Drops folder.
    private func saveImage(from pasteboard: NSPasteboard) -> URL? {
        guard let image = NSImage(pasteboard: pasteboard),
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else { return nil }
        let url = AppPaths.newDropFolder().appendingPathComponent("Dropped Image.png")
        return (try? png.write(to: url)) != nil ? url : nil
    }
}
