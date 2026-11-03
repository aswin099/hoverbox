import AppKit
import HoverboxCore

// `hoverbox`: control Hoverbox shelves from Terminal, scripts and coding agents.
// It sends commands to the running app over a local distributed notification and reads
// the app's status file for `list`, `paths` and `actions`.

let bundleID = "com.arcova.hoverbox"

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data(("hoverbox: " + message + "\n").utf8))
    exit(code)
}

/// The app this tool ships in (…/Hoverbox.app/Contents/SharedSupport/bin/hoverbox), else the installed one.
func appURL() -> URL? {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
    let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
    if bundle.pathExtension == "app" { return bundle }
    return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
}

func isRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
}

/// Starts Hoverbox in the background if it isn't running, and waits until it's listening.
func ensureRunning() {
    guard !isRunning() else { return }
    guard let app = appURL() else { fail("can't find Hoverbox.app. Is it in Applications?") }
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-g", "-j", app.path]
    try? open.run()
    open.waitUntilExit()
    for _ in 0..<50 where !isRunning() { usleep(100_000) }
    guard isRunning() else { fail("Hoverbox didn't start.") }
    usleep(1_200_000)  // let it start listening for commands
}

func status() -> AppStatus {
    ensureRunning()
    guard let status = AppStatus.load() else { fail("Hoverbox hasn't published its shelves yet. Try again.") }
    return status
}

func shelfInfo(_ number: Int?, in status: AppStatus) -> AppStatus.ShelfInfo {
    if let number {
        guard let shelf = status.shelves.first(where: { $0.number == number }) else { fail("there's no shelf \(number). See hoverbox list.") }
        return shelf
    }
    guard let newest = status.shelves.last else { fail("no shelves are open.") }
    return newest
}

let request: CLIRequest
do {
    request = try CLIRequest.parse(Array(CommandLine.arguments.dropFirst()),
                                   directory: FileManager.default.currentDirectoryPath)
} catch {
    fail(error.localizedDescription + "\n\n" + CLIRequest.usage, code: 2)
}

switch request {
case .help:
    print(CLIRequest.usage)
case .version:
    let version = appURL().flatMap { Bundle(url: $0)?.infoDictionary?["CFBundleShortVersionString"] as? String } ?? "unknown"
    print("hoverbox \(version)")
case .list(let json):
    let status = status()
    if json {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(data: (try? encoder.encode(status.shelves)) ?? Data("[]".utf8), encoding: .utf8) ?? "[]")
    } else if status.shelves.isEmpty {
        print("No shelves are open.")
    } else {
        for shelf in status.shelves {
            let items = shelf.itemCount == 1 ? "1 item" : "\(shelf.itemCount) items"
            let count = shelf.isNamed ? "  ·  \(items)" : ""
            print("\(shelf.number)  \(shelf.title)\(shelf.isPinned ? " (pinned)" : "")\(count)")
        }
    }
case .paths(let number):
    shelfInfo(number, in: status()).files.forEach { print($0) }
case .actions:
    status().actions.forEach { print($0) }
case .send(let command):
    if case .newShelf(let paths) = command, let missing = paths.first(where: { !FileManager.default.fileExists(atPath: $0) }) {
        fail("no such file: \(missing)")
    }
    if case .add(let paths, _) = command, let missing = paths.first(where: { !FileManager.default.fileExists(atPath: $0) }) {
        fail("no such file: \(missing)")
    }
    if case .runAction(let name, _) = command,
       !status().actions.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
        fail("no action called \(name). See hoverbox actions.")
    }
    ensureRunning()
    guard let text = command.encoded else { fail("couldn't send that command.") }
    DistributedNotificationCenter.default().postNotificationName(
        Notification.Name(AppCommand.notificationName), object: text, userInfo: nil, deliverImmediately: true)
}
