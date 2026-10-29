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
    public var color: ShelfColor?
    public let createdAt: Date
    /// Set when the shelf goes into the recently closed list.
    public var closedAt: Date?

    public init(id: UUID = UUID(), name: String? = nil, items: [ShelfItem] = [],
                isPinned: Bool = false, origin: Origin? = nil, color: ShelfColor? = nil, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.items = items
        self.isPinned = isPinned
        self.origin = origin
        self.color = color
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

/// A colour tag for telling shelves apart. Shown on the shelf's grabber and in menus.
public enum ShelfColor: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, mint, blue, purple, pink, graphite

    public var displayName: String { rawValue.capitalized }

    /// sRGB as 0xRRGGBB, readable on both light and dark shelves.
    public var rgb: UInt32 {
        switch self {
        case .red: return 0xFF5A52
        case .orange: return 0xFF9F2E
        case .yellow: return 0xF5C518
        case .green: return 0x3CC35F
        case .mint: return 0x34C7B8
        case .blue: return 0x3B82F6
        case .purple: return 0x9B6BF2
        case .pink: return 0xF0619A
        case .graphite: return 0x8E8E93
        }
    }
}

/// Shelves that were closed with things on them, newest first, so they can be reopened.
public struct RecentShelves: Equatable, Sendable {
    public private(set) var shelves: [Shelf]
    public let limit: Int

    public init(shelves: [Shelf] = [], limit: Int = 10) {
        self.shelves = Array(shelves.prefix(limit))
        self.limit = limit
    }

    /// Remembers a closed shelf. Empty shelves aren't worth remembering.
    public mutating func remember(_ shelf: Shelf, at date: Date = Date()) {
        guard !shelf.isEmpty else { return }
        var closed = shelf
        closed.closedAt = date
        closed.isPinned = false
        shelves.removeAll { $0.id == shelf.id }
        shelves.insert(closed, at: 0)
        if shelves.count > limit { shelves.removeLast(shelves.count - limit) }
    }

    /// Removes and returns a shelf for reopening.
    public mutating func take(_ id: UUID) -> Shelf? {
        guard let index = shelves.firstIndex(where: { $0.id == id }) else { return nil }
        var shelf = shelves.remove(at: index)
        shelf.closedAt = nil
        return shelf
    }

    public mutating func clear() {
        shelves.removeAll()
    }
}
