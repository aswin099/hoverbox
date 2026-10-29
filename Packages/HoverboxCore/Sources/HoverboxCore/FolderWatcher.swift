import Darwin
import Foundation

/// Watches one folder and reports items that newly appear in it (not changes inside
/// existing files, and not what was already there when watching started).
/// Hidden files and unfinished downloads are ignored. Reports arrive on the main queue,
/// batched after a short quiet period so a burst of files becomes one report.
public final class FolderWatcher {
    public let folder: URL
    private let debounce: TimeInterval
    private let filter: (URL) -> Bool
    private let onNewItems: ([URL]) -> Void
    private var known: Set<String>
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// Returns nil when the folder can't be opened for watching.
    public init?(folder: URL, debounce: TimeInterval = 0.8, filter: @escaping (URL) -> Bool = { _ in true },
                 onNewItems: @escaping ([URL]) -> Void) {
        self.folder = folder
        self.debounce = debounce
        self.filter = filter
        self.onNewItems = onNewItems
        self.known = Set(Self.listing(of: folder).map(\.lastPathComponent))
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename],
                                                               queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleScan() }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit {
        stop()
    }

    public func stop() {
        pending?.cancel()
        source?.cancel()
        source = nil
    }

    private func scheduleScan() {
        pending?.cancel()
        let scan = DispatchWorkItem { [weak self] in self?.scan() }
        pending = scan
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: scan)
    }

    private func scan() {
        let finished = Self.listing(of: folder).filter(Self.isFinished)
        let fresh = finished.filter { !known.contains($0.lastPathComponent) && filter($0) }
        // Unfinished downloads aren't remembered, so they count as new once they complete.
        known = Set(finished.map(\.lastPathComponent))
        if !fresh.isEmpty { onNewItems(fresh.sorted { $0.lastPathComponent < $1.lastPathComponent }) }
    }

    static func listing(of folder: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil,
                                                                   options: [.skipsHiddenFiles])) ?? []
        return items.filter { !$0.lastPathComponent.hasPrefix(".") }
    }

    /// False for files browsers and download tools are still writing.
    public static func isFinished(_ url: URL) -> Bool {
        !["download", "crdownload", "part", "partial", "tmp", "opdownload"].contains(url.pathExtension.lowercased())
    }
}

/// Recognises screenshots by the marker macOS's screenshot tool writes on every file,
/// so it works whatever language the file names are in.
public enum ScreenshotDetector {
    static let attribute = "com.apple.metadata:kMDItemIsScreenCapture"

    public static func isScreenshot(_ url: URL) -> Bool {
        let size = getxattr(url.path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return false }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, size, 0, 0) }
        guard read == size,
              let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) else { return false }
        return (value as? Bool) ?? ((value as? NSNumber)?.boolValue ?? false)
    }

    /// Where new screenshots are saved: the user's choice in the Screenshot app, else the Desktop.
    public static var screenshotFolder: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        if let location = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location"), !location.isEmpty {
            let expanded = (location as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded, isDirectory: true)
            }
        }
        return home.appendingPathComponent("Desktop", isDirectory: true)
    }
}
