import Foundation
import HoverboxCore

/// Where Hoverbox keeps its own files: the pinned-shelf archive, and a Drops
/// folder for things that arrive as data rather than files (browser images,
/// file promises from Photos or Mail).
enum AppPaths {
    static var support: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hoverbox", isDirectory: true)
    }

    static var archive: URL { support.appendingPathComponent("shelves.json") }
    static var recentArchive: URL { support.appendingPathComponent("recent.json") }

    static var drops: URL { support.appendingPathComponent("Drops", isDirectory: true) }

    /// A fresh folder for one drop, so names from different drops never collide.
    static func newDropFolder() -> URL {
        let folder = drops.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// The per-drop folder holding `url`, if Hoverbox created that file.
    static func dropFolder(of url: URL) -> URL? {
        let folder = url.standardizedFileURL.deletingLastPathComponent()
        return folder.deletingLastPathComponent().path == drops.standardizedFileURL.path ? folder : nil
    }

    /// Deletes drop folders that no remaining shelf refers to.
    static func removeUnusedDrops(keeping shelves: [Shelf]) {
        let used = Set(shelves.flatMap(\.items).compactMap { $0.fileURL.flatMap(dropFolder(of:))?.path })
        let folders = (try? FileManager.default.contentsOfDirectory(at: drops, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where !used.contains(folder.standardizedFileURL.path) {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
