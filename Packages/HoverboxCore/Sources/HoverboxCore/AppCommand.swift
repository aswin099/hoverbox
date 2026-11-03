import Foundation

/// A request to the running app from the `hoverbox` command-line tool. Sent over a distributed
/// notification, which only local processes can post. It deliberately isn't a hoverbox:// link:
/// any web page can open a link, and these commands can run the user's own scripts.
public enum AppCommand: Codable, Equatable, Sendable {
    case newShelf(paths: [String])
    case add(paths: [String], shelf: Int?)
    case runAction(name: String, shelf: Int?)
    case close(shelf: Int)

    public static let notificationName = "com.arcova.hoverbox.command"

    public var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public init?(encoded: String) {
        guard let value = try? JSONDecoder().decode(AppCommand.self, from: Data(encoded.utf8)) else { return nil }
        self = value
    }
}

/// What the app publishes for the command-line tool to read: its open shelves and actions.
public struct AppStatus: Codable, Equatable, Sendable {
    public struct ShelfInfo: Codable, Equatable, Sendable {
        public var number: Int
        public var title: String
        /// True when the user named the shelf, rather than it showing a count like "3 files".
        public var isNamed: Bool
        public var isPinned: Bool
        public var files: [String]
        public var texts: [String]
        public var links: [String]

        public init(number: Int, shelf: Shelf) {
            self.number = number
            title = shelf.title
            isNamed = !(shelf.name ?? "").isEmpty
            isPinned = shelf.isPinned
            files = shelf.items.compactMap { $0.fileURL?.path }
            texts = shelf.items.compactMap { if case .text(let text) = $0.content { return text } else { return nil } }
            links = shelf.items.compactMap { if case .link(let url) = $0.content { return url.absoluteString } else { return nil } }
        }

        public var itemCount: Int { files.count + texts.count + links.count }
    }

    public var shelves: [ShelfInfo]
    public var actions: [String]

    public init(shelves: [ShelfInfo], actions: [String]) {
        self.shelves = shelves
        self.actions = actions
    }

    public static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hoverbox/status.json")
    }

    public static func load(from url: URL = fileURL) -> AppStatus? {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(AppStatus.self, from: $0) }
    }

    public func save(to url: URL = fileURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// What a command line asks for. Parsed here so it can be tested without running anything.
public enum CLIRequest: Equatable, Sendable {
    case help
    case version
    case list(json: Bool)
    case paths(shelf: Int?)
    case actions
    case send(AppCommand)

    public enum ParseError: LocalizedError, Equatable {
        case usage(String)
        public var errorDescription: String? {
            switch self { case .usage(let message): return message }
        }
    }

    public static let usage = """
    hoverbox: control Hoverbox shelves from the command line.

      hoverbox new [FILE…]              Open a new shelf, optionally with files
      hoverbox add FILE… [--shelf N]    Add files to shelf N, or the newest shelf
      hoverbox list [--json]            List open shelves
      hoverbox paths [--shelf N]        Print the files on shelf N, or the newest shelf
      hoverbox actions                  List your actions and the built-in ones
      hoverbox run ACTION [--shelf N]   Run an action on everything on a shelf
      hoverbox close N                  Close shelf N
      hoverbox version                  Print the version
    """

    /// Parses arguments after the program name. File paths are made absolute against `directory`.
    public static func parse(_ arguments: [String], directory: String) throws -> CLIRequest {
        var words = arguments
        guard !words.isEmpty else { return .help }
        let command = words.removeFirst()
        let wantsJSON = words.contains("--json")
        words.removeAll { $0 == "--json" }

        var shelf: Int?
        if let flag = words.firstIndex(of: "--shelf") {
            guard words.indices.contains(flag + 1), let number = Int(words[flag + 1]), number > 0 else {
                throw ParseError.usage("--shelf needs a shelf number, as shown by hoverbox list.")
            }
            shelf = number
            words.removeSubrange(flag...(flag + 1))
        }
        if let unknown = words.first(where: { $0.hasPrefix("--") }) {
            throw ParseError.usage("Unknown option \(unknown).")
        }
        let paths = words.map { path -> String in
            let expanded = (path as NSString).expandingTildeInPath
            let absolute = expanded.hasPrefix("/") ? expanded : (directory as NSString).appendingPathComponent(expanded)
            return (absolute as NSString).standardizingPath
        }

        switch command {
        case "help", "-h", "--help": return .help
        case "version", "--version": return .version
        case "list": return .list(json: wantsJSON)
        case "paths": return .paths(shelf: shelf)
        case "actions": return .actions
        case "new": return .send(.newShelf(paths: paths))
        case "add":
            guard !paths.isEmpty else { throw ParseError.usage("hoverbox add needs at least one file.") }
            return .send(.add(paths: paths, shelf: shelf))
        case "run":
            guard !words.isEmpty else { throw ParseError.usage("hoverbox run needs an action name, as shown by hoverbox actions.") }
            return .send(.runAction(name: words.joined(separator: " "), shelf: shelf))
        case "close":
            guard words.count == 1, let number = Int(words[0]), number > 0 else {
                throw ParseError.usage("hoverbox close needs a shelf number, as shown by hoverbox list.")
            }
            return .send(.close(shelf: number))
        default:
            throw ParseError.usage("Unknown command \(command). Try hoverbox help.")
        }
    }
}
