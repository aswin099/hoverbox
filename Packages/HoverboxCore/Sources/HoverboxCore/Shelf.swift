import Foundation

/// A floating shelf and what's on it. Unpinned shelves are temporary; pinned
/// ones are saved and come back after a restart.
public struct Shelf: Identifiable, Codable, Equatable, Sendable {
    /// Top-left corner of the shelf window in screen coordinates (the shelf grows downward from it).
    public struct Origin: Codable, Equatable, Sendable {
        public var x: Double
        public var y: Double
        public init(x: Double, y: Double) {
            self.x = x
            self.y = y
        }
    }

    public let id: UUID
    public var name: String?
    public var items: [ShelfItem]
    public var isPinned: Bool
    public var origin: Origin?
    public let createdAt: Date

    public init(id: UUID = UUID(), name: String? = nil, items: [ShelfItem] = [],
                isPinned: Bool = false, origin: Origin? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.isPinned = isPinned
        self.origin = origin
        self.createdAt = createdAt
    }

    public var isEmpty: Bool { items.isEmpty }

    /// Appends items, skipping anything already on the shelf. Returns what was added.
    @discardableResult
    public mutating func add(_ newItems: [ShelfItem]) -> [ShelfItem] {
        var keys = Set(items.map(\.dedupeKey))
        var added: [ShelfItem] = []
        for item in newItems where keys.insert(item.dedupeKey).inserted {
            items.append(item)
            added.append(item)
        }
        return added
    }

    public mutating func remove(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }

    /// Moves one item so it ends up before the item now at `destination` (or last).
    public mutating func move(_ id: UUID, to destination: Int) {
        move([id], to: destination)
    }

    /// Moves a group of items, keeping their order, so they end up just before
    /// the item now at `destination` (or last when `destination` is past the end).
    public mutating func move(_ ids: [UUID], to destination: Int) {
        let moving = Set(ids)
        let block = items.filter { moving.contains($0.id) }
        guard !block.isEmpty else { return }
        let anchor = items[min(max(0, destination), items.count)...].first { !moving.contains($0.id) }?.id
        items.removeAll { moving.contains($0.id) }
        let index = anchor.flatMap { id in items.firstIndex { $0.id == id } } ?? items.count
        items.insert(contentsOf: block, at: index)
    }

    /// Points a file item at a new location, for example after renaming the file.
    public mutating func updateFile(_ id: UUID, to url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }), items[index].fileURL != nil else { return }
        items[index].pointTo(url)
    }

    /// Items in shelf order, limited to `ids` (all items when `ids` is empty).
    public func items(in ids: Set<UUID>) -> [ShelfItem] {
        ids.isEmpty ? items : items.filter { ids.contains($0.id) }
    }

    public var title: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return Self.summary(of: items)
    }

    /// "3 files", "1 link", "4 items" and so on.
    public static func summary(of items: [ShelfItem]) -> String {
        guard !items.isEmpty else { return "Empty shelf" }
        var files = 0, texts = 0, links = 0
        for item in items {
            switch item.content {
            case .file: files += 1
            case .text: texts += 1
            case .link: links += 1
            }
        }
        let count = items.count
        func plural(_ word: String) -> String { "\(count) \(word)\(count == 1 ? "" : "s")" }
        if files == count { return plural("file") }
        if links == count { return plural("link") }
        if texts == count { return plural("text snippet") }
        return plural("item")
    }
}
