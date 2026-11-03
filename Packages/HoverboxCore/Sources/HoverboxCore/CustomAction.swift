import Foundation

/// A named action the user builds from steps, such as "Resize to 1280, then ZIP".
/// Each step takes the files the previous one produced. Originals are never changed:
/// every step writes new files into its own folder.
public struct CustomAction: Identifiable, Codable, Equatable, Sendable {
    public enum Step: Codable, Equatable, Sendable {
        case resizeLongestSide(Int)
        case resizePercent(Int)
        case convert(ImageFormat)
        case compress
        case zip
        /// A shell script run with the files as its arguments (see `ActionRunner`).
        case script(String)
    }

    public let id: UUID
    public var name: String
    public var steps: [Step]

    public init(id: UUID = UUID(), name: String, steps: [Step]) {
        self.id = id
        self.name = name
        self.steps = steps
    }
}

public enum ActionError: LocalizedError, Equatable {
    case scriptFailed(status: Int32, message: String)
    case scriptTimedOut

    public var errorDescription: String? {
        switch self {
        case .scriptFailed(let status, let message):
            return message.isEmpty ? "The script failed (exit code \(status))." : "The script failed: \(message)"
        case .scriptTimedOut:
            return "The script took too long and was stopped."
        }
    }
}

/// What a custom action produced.
public struct ActionResult: Equatable, Sendable {
    public var files: [URL]
    /// Whatever the last script printed, if anything.
    public var text: String?

    public init(files: [URL], text: String? = nil) {
        self.files = files
        self.text = text
    }
}

/// Runs custom actions. Blocks; call it off the main thread.
///
/// A script step runs in `zsh` with the current files as `$@`. To produce new files it writes
/// them into `$HOVERBOX_OUTPUT` (also the working directory); if it writes none, the files pass
/// through unchanged. Anything printed to stdout becomes text on the shelf.
public enum ActionRunner {
    public static func run(_ action: CustomAction, on files: [URL], in folder: URL,
                           scriptTimeout: TimeInterval = 120) throws -> ActionResult {
        var current = files
        var text: String?
        for (index, step) in action.steps.enumerated() {
            let stepFolder = folder.appendingPathComponent("step-\(index + 1)", isDirectory: true)
            try FileManager.default.createDirectory(at: stepFolder, withIntermediateDirectories: true)
            switch step {
            case .resizeLongestSide(let side):
                current = try resize(current, to: .longestSide(side), in: stepFolder)
            case .resizePercent(let percent):
                current = try resize(current, to: .percent(percent), in: stepFolder)
            case .convert(let format):
                current = try current.map { url in
                    guard ImageTool.isImage(url) else { return url }
                    let same = ImageFormat(url: url) == format
                    let output = OutputNaming.url(in: stepFolder, for: url.lastPathComponent, suffix: same ? "converted" : nil,
                                                  fileExtension: format.fileExtension)
                    try ImageTool.write(url, to: output, format: format, quality: 0.9)
                    return output
                }
            case .compress:
                current = try current.map { try compress($0, in: stepFolder) }
            case .zip:
                guard !current.isEmpty else { continue }
                let name = current.count == 1 ? current[0].lastPathComponent : "Archive"
                let output = OutputNaming.url(in: stepFolder, for: name + ".zip", fileExtension: "zip")
                try Archiver.zip(current, to: output)
                current = [output]
            case .script(let script):
                let result = try runScript(script, files: current, output: stepFolder, timeout: scriptTimeout)
                if !result.files.isEmpty { current = result.files }
                if let printed = result.text { text = printed }
            }
        }
        return ActionResult(files: current, text: text)
    }

    private static func resize(_ files: [URL], to target: ResizeTarget, in folder: URL) throws -> [URL] {
        try files.map { url in
            guard ImageTool.isImage(url) else { return url }
            let format = ImageFormat(url: url).flatMap { ImageFormat.writable.contains($0) ? $0 : nil } ?? .png
            let longest = ImageTool.pixelSize(of: url).map { Int(max($0.width, $0.height)) } ?? 0
            let output = OutputNaming.url(in: folder, for: url.lastPathComponent, suffix: target.label,
                                          fileExtension: format.fileExtension)
            try ImageTool.write(url, to: output, format: format, longestSide: target.longestSide(forOriginal: longest), quality: 0.9)
            return output
        }
    }

    /// Keeps the smaller file, like the Compress Images action.
    private static func compress(_ url: URL, in folder: URL) throws -> URL {
        guard ImageTool.isImage(url) else { return url }
        let format = ImageTool.compressedFormat(for: url)
        let output = OutputNaming.url(in: folder, for: url.lastPathComponent, suffix: "compressed",
                                      fileExtension: format.fileExtension)
        try ImageTool.write(url, to: output, format: format, quality: 0.7)
        let size = { (file: URL) in (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        guard size(output) < size(url) else {
            try? FileManager.default.removeItem(at: output)
            return url
        }
        return output
    }

    private static func runScript(_ script: String, files: [URL], output: URL, timeout: TimeInterval) throws -> ActionResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", script, "hoverbox"] + files.map(\.path)
        process.currentDirectoryURL = output
        var environment = ProcessInfo.processInfo.environment
        environment["HOVERBOX_OUTPUT"] = output.path
        process.environment = environment
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()
        // Read on another queue so a chatty script can't fill the pipe and stall.
        let group = DispatchGroup()
        let collected = PipeOutput()
        DispatchQueue.global().async(group: group) { collected.out = stdout.fileHandleForReading.readDataToEndOfFile() }
        DispatchQueue.global().async(group: group) { collected.err = stderr.fileHandleForReading.readDataToEndOfFile() }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            throw ActionError.scriptTimedOut
        }
        group.wait()
        guard process.terminationStatus == 0 else {
            let message = String(data: collected.err, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw ActionError.scriptFailed(status: process.terminationStatus, message: message)
        }
        let made = (try? FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil,
                                                                  options: [.skipsHiddenFiles])) ?? []
        let printed = String(data: collected.out, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return ActionResult(files: made.sorted { $0.lastPathComponent < $1.lastPathComponent },
                            text: printed.isEmpty ? nil : printed)
    }
}

private final class PipeOutput: @unchecked Sendable {
    var out = Data()
    var err = Data()
}
