import Foundation

/// One thing on a shelf. Files are held by reference: the shelf never copies
/// or moves them on its own. A bookmark lets a shelf follow a file that was
/// renamed or moved while it sat there.
public struct ShelfItem: Identifiable, Codable, Equatable, Sendable {
    public enum Content: Codable, Equatable, Sendable {
        case file(URL)
        case text(String)
        case link(URL)
    }

    public let id: UUID
    public var content: Content
    public var bookmark: Data?
    public let addedAt: Date

    public init(content: Content, id: UUID = UUID(), addedAt: Date = Date()) {
        self.id = id
        self.content = content
        self.addedAt = addedAt
        if case .file(let url) = content {
            bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
    }

    public static func file(_ url: URL) -> ShelfItem { ShelfItem(content: .file(url)) }
    public static func text(_ text: String) -> ShelfItem { ShelfItem(content: .text(text)) }
    public static func link(_ url: URL) -> ShelfItem { ShelfItem(content: .link(url)) }

    public var fileURL: URL? {
        if case .file(let url) = content { return url }
        return nil
    }

    public var displayName: String {
        switch content {
        case .file(let url):
            return url.lastPathComponent
        case .text(let text):
            let line = text.split(whereSeparator: \.isNewline)
                .first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count > 80 ? String(trimmed.prefix(80)) + "…" : trimmed
        case .link(let url):
            let path = url.path == "/" ? "" : url.path
            return (url.host ?? url.absoluteString) + path
        }
    }

    /// Key used to skip duplicates when the same thing is dropped twice.
    var dedupeKey: String {
        switch content {
        case .file(let url): return "f:" + url.standardizedFileURL.path
        case .text(let text): return "t:" + text
        case .link(let url): return "l:" + url.absoluteString
        }
    }

    /// Follows the bookmark when a file is no longer at its path. `isMissing`
    /// is true when the file is gone or sits in the Trash.
    public func refreshed() -> (item: ShelfItem, isMissing: Bool) {
        guard case .file(let url) = content else { return (self, false) }
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: url.path) { return (self, Self.isInTrash(url)) }
        guard let bookmark else { return (self, true) }
        var isStale = false
        guard let resolved = try? URL(resolvingBookmarkData: bookmark, options: [.withoutUI],
                                      relativeTo: nil, bookmarkDataIsStale: &isStale),
              fileManager.fileExists(atPath: resolved.path),
              !Self.isInTrash(resolved) else { return (self, true) }
        var updated = self
        updated.content = .file(resolved)
        if isStale {
            updated.bookmark = try? resolved.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        }
        return (updated, false)
    }

    private static func isInTrash(_ url: URL) -> Bool {
        url.standardizedFileURL.pathComponents.contains(".Trash")
    }
}
