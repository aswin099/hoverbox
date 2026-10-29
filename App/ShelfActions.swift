import AppKit
import HoverboxCore

/// Actions that can be dropped onto while dragging over a shelf, without collecting first.
enum InstantAction: CaseIterable, Identifiable {
    case airDrop, share, zip, text

    var id: Self { self }

    var title: String {
        switch self {
        case .airDrop: return "AirDrop"
        case .share: return "Share"
        case .zip: return "ZIP"
        case .text: return "Text"
        }
    }

    var symbol: String {
        switch self {
        case .airDrop: return "airplayaudio"
        case .share: return "square.and.arrow.up"
        case .zip: return "doc.zipper"
        case .text: return "text.viewfinder"
        }
    }

    var help: String {
        switch self {
        case .airDrop: return "Drop to send with AirDrop"
        case .share: return "Drop to share"
        case .zip: return "Drop to make a ZIP"
        case .text: return "Drop images or PDFs to copy their text"
        }
    }
}

/// File actions on shelf items. Originals are never changed: results are new files
/// in Hoverbox's Drops folder, added to the shelf and selected, ready to drag out.
extension ShelfController {
    static let resizeTargets: [ResizeTarget] = [.percent(25), .percent(50), .percent(75),
                                                .longestSide(3840), .longestSide(2560), .longestSide(1920),
                                                .longestSide(1280), .longestSide(800)]

    /// What the Actions menu works on: the selection, or the whole shelf.
    var actionTargets: [ShelfItem] {
        shelf.items(in: selection).filter { !missing.contains($0.id) }
    }

    /// The chevron menu: shelf options first, then actions on the selection or everything.
    func showActionsMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(ActionMenuItem(shelf.isPinned ? "Unpin Shelf" : "Pin Shelf") { [weak self] in self?.togglePin() })
        menu.addItem(ActionMenuItem("Name Shelf…") { [weak self] in self?.promptForName() })
        let colour = NSMenuItem(title: "Colour", action: nil, keyEquivalent: "")
        let colours = NSMenu()
        let none = ActionMenuItem("None") { [weak self] in self?.setColor(nil) }
        none.state = shelf.color == nil ? .on : .off
        colours.addItem(none)
        for option in ShelfColor.allCases {
            let item = ActionMenuItem(option.displayName) { [weak self] in self?.setColor(option) }
            item.image = option.swatch()
            item.state = shelf.color == option ? .on : .off
            colours.addItem(item)
        }
        colour.submenu = colours
        menu.addItem(colour)
        if !shelf.isEmpty {
            menu.addItem(ActionMenuItem(isExpanded ? "Show as Pile" : "Show All Items") { [weak self] in
                guard let self else { return }
                setExpanded(!isExpanded)
            })
            menu.addItem(.separator())
            let header = NSMenuItem.sectionHeader(title: selection.isEmpty ? "All Items" : "Selected Items")
            menu.addItem(header)
            let actions = actionsMenu(for: actionTargets)
            for item in actions.items {
                actions.removeItem(item)
                menu.addItem(item)
            }
        }
        menu.popUp(positioning: nil, at: panel.mouseLocationOutsideOfEventStream, in: panel.contentView)
    }

    /// The action items, for the header button and the right-click menu.
    func actionsMenu(for targets: [ShelfItem]) -> NSMenu {
        let menu = NSMenu()
        let files = targets.compactMap(\.fileURL)
        let images = files.filter(ImageTool.isImage)
        let archives = files.filter(Archiver.isArchive)
        let readable = files.filter(TextRecognizer.canRead)

        func item(_ title: String, enabled: Bool = true, _ action: @escaping () -> Void) -> NSMenuItem {
            let menuItem = ActionMenuItem(title, handler: action)
            menuItem.isEnabled = enabled
            return menuItem
        }
        func count(_ n: Int, _ noun: String) -> String { n == 1 ? "1 \(noun)" : "\(n) \(noun)s" }

        menu.autoenablesItems = false
        menu.addItem(item("Share…", enabled: !targets.isEmpty) { [weak self] in self?.share(targets) })
        menu.addItem(item("AirDrop…", enabled: !targets.isEmpty) { [weak self] in self?.airDrop(targets) })
        let favourites = Favourite.all
        let folders = favourites.filter { !$0.isApp }, apps = favourites.filter(\.isApp)
        if !folders.isEmpty {
            for move in [false, true] {
                let parent = NSMenuItem(title: move ? "Move To" : "Copy To", action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                for folder in folders {
                    let entry = item(folder.name) { [weak self] in self?.copy(files, into: folder.url, move: move) }
                    entry.image = folder.icon(size: 16)
                    submenu.addItem(entry)
                }
                parent.submenu = submenu
                parent.isEnabled = !files.isEmpty
                menu.addItem(parent)
            }
        }
        if !apps.isEmpty {
            let parent = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
            let submenu = NSMenu()
            for app in apps {
                let entry = item(app.name) { [weak self] in self?.open(files, with: app.url) }
                entry.image = app.icon(size: 16)
                submenu.addItem(entry)
            }
            parent.submenu = submenu
            parent.isEnabled = !files.isEmpty
            menu.addItem(parent)
        }
        menu.addItem(.separator())
        menu.addItem(item(files.isEmpty ? "Compress to ZIP" : "Compress \(count(files.count, "Item")) to ZIP",
                          enabled: !files.isEmpty) { [weak self] in self?.zip(files) })
        if !archives.isEmpty {
            menu.addItem(item("Unzip \(count(archives.count, "Archive"))") { [weak self] in self?.unzip(archives) })
        }
        menu.addItem(.separator())

        let resize = NSMenuItem(title: "Resize Images", action: nil, keyEquivalent: "")
        let resizeMenu = NSMenu()
        for (index, target) in Self.resizeTargets.enumerated() {
            if index == 3 { resizeMenu.addItem(.separator()) }
            let title = index < 3 ? "\(target.label) of Original Size" : "Longest Side \(target.label)"
            resizeMenu.addItem(item(title) { [weak self] in self?.resize(images, to: target) })
        }
        resize.submenu = resizeMenu
        resize.isEnabled = !images.isEmpty
        menu.addItem(resize)

        let convert = NSMenuItem(title: "Convert Images To", action: nil, keyEquivalent: "")
        let convertMenu = NSMenu()
        for format in ImageFormat.writable {
            convertMenu.addItem(item(format.displayName) { [weak self] in self?.convert(images, to: format) })
        }
        convert.submenu = convertMenu
        convert.isEnabled = !images.isEmpty
        menu.addItem(convert)

        menu.addItem(item("Compress Images (Smaller Files)", enabled: !images.isEmpty) { [weak self] in self?.compress(images) })
        menu.addItem(.separator())
        menu.addItem(item("Extract Text", enabled: !readable.isEmpty) { [weak self] in self?.extractText(readable) })
        return menu
    }

    // MARK: Sharing

    func share(_ items: [ShelfItem]) {
        let objects: [Any] = items.map { item in
            switch item.content {
            case .file(let url), .link(let url): return url
            case .text(let text): return text
            }
        }
        guard !objects.isEmpty, let view = panel.contentView else { return }
        NSApp.activate(ignoringOtherApps: true)
        let anchor = NSRect(x: view.bounds.midX - 1, y: view.bounds.maxY - 34, width: 2, height: 2)
        NSSharingServicePicker(items: objects).show(relativeTo: anchor, of: view, preferredEdge: .maxY)
    }

    func airDrop(_ items: [ShelfItem]) {
        let objects: [Any] = items.compactMap { item in
            switch item.content {
            case .file(let url), .link(let url): return url
            case .text: return nil
            }
        }
        guard let service = NSSharingService(named: .sendViaAirDrop), service.canPerform(withItems: objects) else {
            showStatus("AirDrop can't send these items", isError: true)
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: objects)
    }

    // MARK: Favourites

    /// Copies (or moves) files into a folder. Moved files stay on the shelf at their new place.
    func copy(_ urls: [URL], into folder: URL, move: Bool) {
        guard !urls.isEmpty else { return }
        run(move ? "Moving…" : "Copying…") {
            for url in urls {
                let target = OutputNaming.url(in: folder, for: url.lastPathComponent, fileExtension: url.pathExtension)
                if move {
                    try FileManager.default.moveItem(at: url, to: target)
                } else {
                    try FileManager.default.copyItem(at: url, to: target)
                }
            }
            let what = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) items"
            return ([], "\(move ? "Moved" : "Copied") \(what) to \(folder.lastPathComponent)")
        } after: { [weak self] _ in
            if move { self?.refreshFiles() }
        }
    }

    func open(_ urls: [URL], with app: URL) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        showStatus("Opened in \(app.deletingPathExtension().lastPathComponent)")
    }

    /// Something was dropped on a favourite in the drop strip: apps open it; folders get a
    /// copy, or the original when Command is held.
    func drop(_ items: [ShelfItem], on favourite: Favourite) {
        let files = items.compactMap(\.fileURL)
        guard !files.isEmpty else {
            showStatus("Only files can go to \(favourite.name)", isError: true)
            return
        }
        if favourite.isApp {
            open(files, with: favourite.url)
        } else {
            copy(files, into: favourite.url, move: NSEvent.modifierFlags.contains(.command))
        }
    }

    // MARK: Files

    func zip(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        let folder = AppPaths.newDropFolder()
        let name = urls.count == 1 ? urls[0].lastPathComponent : "Archive"
        let output = OutputNaming.url(in: folder, for: name + ".zip", fileExtension: "zip")
        run("Compressing…") {
            try Archiver.zip(urls, to: output)
            return ([.file(output)], "Made \(output.lastPathComponent)")
        }
    }

    func unzip(_ archives: [URL]) {
        let folder = AppPaths.newDropFolder()
        run("Unzipping…") {
            var items: [ShelfItem] = []
            for archive in archives {
                let target = archives.count == 1 ? folder
                    : folder.appendingPathComponent(archive.deletingPathExtension().lastPathComponent, isDirectory: true)
                items += try Archiver.unzip(archive, into: target).map(ShelfItem.file)
            }
            return (items, items.count == 1 ? "Unzipped 1 item" : "Unzipped \(items.count) items")
        }
    }

    // MARK: Images

    func resize(_ images: [URL], to target: ResizeTarget) {
        let folder = AppPaths.newDropFolder()
        run("Resizing…") {
            let items = try images.map { url -> ShelfItem in
                let format = ImageFormat(url: url).flatMap { ImageFormat.writable.contains($0) ? $0 : nil } ?? .png
                let longest = ImageTool.pixelSize(of: url).map { Int(max($0.width, $0.height)) } ?? 0
                let output = OutputNaming.url(in: folder, for: url.lastPathComponent, suffix: target.label,
                                              fileExtension: format.fileExtension)
                try ImageTool.write(url, to: output, format: format,
                                    longestSide: target.longestSide(forOriginal: longest), quality: 0.9)
                return .file(output)
            }
            return (items, Self.count(items.count, "image", "resized"))
        }
    }

    func convert(_ images: [URL], to format: ImageFormat) {
        let folder = AppPaths.newDropFolder()
        run("Converting…") {
            let items = try images.map { url -> ShelfItem in
                let sameFormat = ImageFormat(url: url) == format
                let output = OutputNaming.url(in: folder, for: url.lastPathComponent, suffix: sameFormat ? "converted" : nil,
                                              fileExtension: format.fileExtension)
                try ImageTool.write(url, to: output, format: format, quality: 0.9)
                return .file(output)
            }
            return (items, Self.count(items.count, "image", "converted to \(format.displayName)"))
        }
    }

    /// Re-encodes at a lower quality; keeps a result only when it's actually smaller.
    func compress(_ images: [URL]) {
        let folder = AppPaths.newDropFolder()
        run("Compressing images…") {
            var items: [ShelfItem] = []
            var saved: Int64 = 0
            for url in images {
                let format = ImageTool.compressedFormat(for: url)
                let output = OutputNaming.url(in: folder, for: url.lastPathComponent, suffix: "compressed",
                                              fileExtension: format.fileExtension)
                try ImageTool.write(url, to: output, format: format, quality: 0.7)
                let before = Self.fileSize(url), after = Self.fileSize(output)
                if after < before {
                    items.append(.file(output))
                    saved += before - after
                } else {
                    try? FileManager.default.removeItem(at: output)
                }
            }
            guard !items.isEmpty else { return ([], "Already as small as they get") }
            let amount = ByteCountFormatter.string(fromByteCount: saved, countStyle: .file)
            return (items, Self.count(items.count, "image", "compressed") + ", \(amount) smaller")
        }
    }

    // MARK: Text

    func extractText(_ files: [URL]) {
        run("Reading text…") {
            let text = try files.map(TextRecognizer.text(in:))
                .filter { !$0.isEmpty }
                .joined(separator: "\n\n")
            guard !text.isEmpty else { return ([], "No text found") }
            return ([.text(text)], "Text copied and added to the shelf")
        } after: { items in
            if let text = items.first { self.copyToPasteboard([text]) }
        }
    }

    // MARK: Running

    /// Runs `work` off the main thread, then adds and selects what it made and shows its message.
    func run(_ working: String,
             work: @escaping @Sendable () throws -> (items: [ShelfItem], message: String),
             after: @escaping @MainActor ([ShelfItem]) -> Void = { _ in }) {
        showStatus(working, sticky: true)
        Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try work() }
            await MainActor.run {
                guard let self else { return }
                switch result {
                case .success(let output):
                    if !output.items.isEmpty {
                        self.add(output.items)
                        self.selection = Set(output.items.map(\.id))
                    }
                    after(output.items)
                    self.showStatus(output.message)
                case .failure(let error):
                    self.showStatus(error.localizedDescription, isError: true)
                }
            }
        }
    }

    /// Runs a drop-onto action on items that were never put on the shelf.
    func runInstant(_ action: InstantAction, on items: [ShelfItem]) {
        let files = items.compactMap(\.fileURL)
        switch action {
        case .airDrop: airDrop(items)
        case .share: share(items)
        case .zip:
            if files.isEmpty { showStatus("Only files can go in a ZIP", isError: true) } else { zip(files) }
        case .text:
            let readable = files.filter(TextRecognizer.canRead)
            if readable.isEmpty { showStatus("Drop images or PDFs to read their text", isError: true) } else { extractText(readable) }
        }
    }

    private nonisolated static func count(_ n: Int, _ noun: String, _ verb: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s") \(verb)"
    }

    private nonisolated static func fileSize(_ url: URL) -> Int64 {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
    }
}

/// How the expanded shelf lays out items. Remembered across shelves.
enum ShelfLayout: String {
    case grid, list

    static var saved: ShelfLayout {
        get { ShelfLayout(rawValue: UserDefaults.standard.string(forKey: "shelfLayout") ?? "") ?? .grid }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "shelfLayout") }
    }
}

/// A folder or app the user keeps handy as a drop target (Settings ▸ Favourites).
struct Favourite: Identifiable, Hashable {
    let url: URL

    var id: String { url.path }
    var isApp: Bool { url.pathExtension == "app" }
    var name: String { FileManager.default.displayName(atPath: url.path) }

    func icon(size: CGFloat) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: size, height: size)
        return image
    }

    /// Favourites that still exist, in the order they were added.
    static var all: [Favourite] {
        Prefs.favourites.filter { FileManager.default.fileExists(atPath: $0) }
            .map { Favourite(url: URL(fileURLWithPath: $0)) }
    }
}

extension ShelfColor {
    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }

    /// True for colours that need dark text on top.
    var isLight: Bool {
        let r = Double((rgb >> 16) & 0xFF) / 255, g = Double((rgb >> 8) & 0xFF) / 255, b = Double(rgb & 0xFF) / 255
        return 0.2126 * r + 0.7152 * g + 0.0722 * b > 0.6
    }

    /// A small round swatch for menus.
    func swatch(size: CGFloat = 12) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            nsColor.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }
}
