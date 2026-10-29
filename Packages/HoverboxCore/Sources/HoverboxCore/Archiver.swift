import Foundation

public enum ArchiverError: LocalizedError, Equatable {
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .failed(let message): return message.isEmpty ? "The archive couldn't be made or opened." : message
        }
    }
}

/// Makes and opens ZIP archives with macOS's own `ditto`, the tool Finder's
/// Compress command uses, so archives behave exactly like Finder's.
public enum Archiver {
    /// Zips `items` into `output`. One item keeps its own folder at the top; several
    /// items sit side by side at the top level, as with Finder's "Archive.zip".
    public static func zip(_ items: [URL], to output: URL) throws {
        guard !items.isEmpty else { return }
        if items.count == 1 {
            try ditto(["-c", "-k", "--sequesterRsrc", "--keepParent", items[0].path, output.path])
            return
        }
        // Several items: clone them into one staging folder (instant and space-free on APFS), then zip its contents.
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("Hoverbox-zip-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        for item in items {
            let target = OutputNaming.url(in: staging, for: item.lastPathComponent,
                                          fileExtension: item.pathExtension)
            try FileManager.default.copyItem(at: item, to: target)
        }
        try ditto(["-c", "-k", "--sequesterRsrc", staging.path, output.path])
    }

    /// Extracts `archive` into `directory` and returns the top-level items it contained.
    @discardableResult
    public static func unzip(_ archive: URL, into directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ditto(["-x", "-k", archive.path, directory.path])
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        return contents.filter { $0.lastPathComponent != "__MACOSX" && $0.lastPathComponent != ".DS_Store" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    public static func isArchive(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "zip"
    }

    private static func ditto(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ArchiverError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }
}
