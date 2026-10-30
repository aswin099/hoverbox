import AppKit
import UniformTypeIdentifiers

/// "Hoverbox" in the Share menu. Collects what was shared (files, images, links, text),
/// hands it to the Hoverbox app as a hoverbox://share link, and closes at once.
final class ShareViewController: NSViewController {
    override var nibName: NSNib.Name? { nil }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let collected = Collected()
        let group = DispatchGroup()
        for provider in providers {
            group.enter()
            load(provider, into: collected) { group.leave() }
        }
        group.notify(queue: .main) { [weak self] in
            var components = URLComponents()
            components.scheme = "hoverbox"
            components.host = "share"
            components.queryItems = collected.queryItems
            if let url = components.url, !collected.queryItems.isEmpty {
                NSWorkspace.shared.open(url)
            }
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Files first, then images (saved to a file), links, and plain text.
    private func load(_ provider: NSItemProvider, into collected: Collected, done: @escaping () -> Void) {
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
                if let url = Self.url(from: item), url.isFileURL { collected.add("path", url.path) }
                done()
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data {
                    let url = FileManager.default.temporaryDirectory
                        .appendingPathComponent("Shared Image \(UUID().uuidString.prefix(6)).png")
                    if (try? data.write(to: url)) != nil { collected.add("path", url.path) }
                }
                done()
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { item, _ in
                if let url = Self.url(from: item) { collected.add(url.isFileURL ? "path" : "link", url.isFileURL ? url.path : url.absoluteString) }
                done()
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { item, _ in
                if let text = item as? String { collected.add("text", text) }
                done()
            }
        } else {
            done()
        }
    }

    private static func url(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL { return url }
        if let data = item as? Data { return URL(dataRepresentation: data, relativeTo: nil) }
        if let string = item as? String { return URL(string: string) }
        return nil
    }
}

/// Thread-safe collection of query items, filled from the providers' callbacks.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [URLQueryItem] = []

    func add(_ name: String, _ value: String) {
        lock.lock()
        items.append(URLQueryItem(name: name, value: value))
        lock.unlock()
    }

    var queryItems: [URLQueryItem] {
        lock.lock()
        defer { lock.unlock() }
        return items
    }
}
