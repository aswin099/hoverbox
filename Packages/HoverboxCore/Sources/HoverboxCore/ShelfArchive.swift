import Foundation

/// Saves pinned shelves as JSON. Unpinned shelves are temporary by design and
/// are never written to disk. The file holds paths and bookmarks only, never
/// file contents.
public struct ShelfArchive {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() -> [Shelf] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Shelf].self, from: data)) ?? []
    }

    public func save(_ shelves: [Shelf]) throws {
        let pinned = shelves.filter(\.isPinned)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(pinned).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

/// Decides whether a drag should be watched for a shake.
public struct ShakeRules: Equatable, Sendable {
    public var isEnabled: Bool
    public var excludedBundleIDs: Set<String>

    public init(isEnabled: Bool, excludedBundleIDs: Set<String>) {
        self.isEnabled = isEnabled
        self.excludedBundleIDs = excludedBundleIDs
    }

    public func shouldWatch(frontmostBundleID: String?) -> Bool {
        guard isEnabled else { return false }
        guard let frontmostBundleID else { return true }
        return !excludedBundleIDs.contains(frontmostBundleID)
    }
}
