import HoverboxCore
import PDFKit
import QuickLookThumbnailing
import SwiftUI

/// A shelf has two faces. Compact: the pile with its name, as it first appears.
/// Expanded (click the name or the pile): every item in a grid or list.
struct ShelfView: View {
    @ObservedObject var controller: ShelfController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let space = "shelf"
    /// How long the card takes to open or close; the window shrinks after this.
    static let cardAnimationDuration: TimeInterval = 0.45

    private var shelf: Shelf { controller.shelf }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 22, style: .continuous) }

    var body: some View {
        let expanded = controller.isExpanded
        let card = expanded ? ShelfPanel.expandedCard : ShelfPanel.compactCard
        ZStack(alignment: .top) {
            // Each face is laid out at its own final size and revealed by the card as it
            // grows or shrinks, so nothing reflows mid-animation.
            if expanded {
                ExpandedShelf(controller: controller)
                    .frame(width: ShelfPanel.expandedCard.width, height: ShelfPanel.expandedCard.height)
                    .transition(.asymmetric(insertion: .opacity.animation(fade(0.22, delay: 0.06)),
                                            removal: .opacity.animation(fade(0.14))))
            } else {
                CompactShelf(controller: controller)
                    .frame(width: ShelfPanel.compactCard.width, height: ShelfPanel.compactCard.height)
                    .transition(.asymmetric(insertion: .opacity.animation(fade(0.22, delay: 0.12)),
                                            removal: .opacity.animation(fade(0.12))))
            }
        }
        .frame(width: card.width, height: card.height, alignment: .top)
        .overlay(alignment: .bottom) {
            if controller.isDropTargeted {
                InstantActionStrip(controller: controller, compact: !expanded)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: controller.isDropTargeted)
        .coordinateSpace(name: ShelfView.space)
        .onPreferenceChange(RowFramesKey.self) { controller.rowFrames = $0 }
        .background(.regularMaterial, in: shape)
        .overlay(
            shape.strokeBorder(controller.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.14),
                               lineWidth: controller.isDropTargeted ? 2 : 0.5)
        )
        .clipShape(shape)
        // A soft shadow drawn by the card itself (the window has none), so it follows the animation.
        .background(shape.fill(Color.black.opacity(0.32)).blur(radius: 12).offset(y: 6).padding(2))
        .animation(reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.86), value: expanded)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, ShelfPanel.margin)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelf: \(shelf.title)")
    }

    private func fade(_ duration: Double, delay: Double = 0) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration).delay(delay)
    }
}

/// A round, quiet button used in both shelf headers.
struct CircleButton: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Color.primary.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

// MARK: Compact

struct CompactShelf: View {
    @ObservedObject var controller: ShelfController
    private var shelf: Shelf { controller.shelf }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                CircleButton(symbol: "xmark", label: "Close shelf") { controller.close() }
                Spacer()
                if shelf.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Pinned")
                }
                Spacer()
                CircleButton(symbol: "chevron.down", label: "Shelf options and actions") { controller.showActionsMenu() }
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            if shelf.isEmpty {
                emptyState
            } else {
                pile
                namePill
                    .padding(.bottom, 14)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(controller.isDropTargeted ? Color.accentColor : .secondary)
            Text("Drop here")
                .font(.system(size: 13, weight: .medium))
            if let status = controller.status {
                Text(status.text)
                    .font(.system(size: 11))
                    .foregroundStyle(status.isError ? Color.orange : Color.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                .foregroundStyle(Color.secondary.opacity(0.45))
        )
        .padding(12)
    }

    /// Up to three items fanned out. Drag it to take everything; click it to see every item.
    private var pile: some View {
        let shown = Array(shelf.items.prefix(3).reversed())
        let angles: [Double] = shown.count == 1 ? [0] : shown.count == 2 ? [-7, 5] : [-10, 8, -1]
        return ZStack {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                ItemIcon(item: item, size: 96)
                    .rotationEffect(.degrees(angles[index]))
                    .offset(x: CGFloat(index - shown.count / 2) * 6)
                    .shadow(color: .black.opacity(0.18), radius: 4, y: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .overlay(
            DragSource(items: { controller.shelf.items },
                       onClick: { _ in controller.setExpanded(true) },
                       onEnded: { controller.didDragOut(ids: $0, operation: $1, at: $2) })
        )
        .help("Drag to move everything; click to see every item")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag all \(shelf.items.count) items")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { controller.setExpanded(true) }
    }

    private var pillTitle: String {
        if let name = shelf.name, !name.isEmpty { return name }
        return shelf.items.count == 1 ? shelf.items[0].displayName : shelf.title.localizedCapitalized
    }

    private var namePill: some View {
        Button { controller.setExpanded(true) } label: {
            HStack(spacing: 6) {
                Text(controller.status?.text ?? pillTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(controller.status?.isError == true ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if controller.status == nil, shelf.name != nil, shelf.items.count > 1 {
                    Text("\(shelf.items.count)")
                        .font(.system(size: 12, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .frame(maxWidth: 176)
            .background(Color.primary.opacity(0.08), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Show every item")
    }
}

// MARK: Expanded

struct ExpandedShelf: View {
    @ObservedObject var controller: ShelfController
    @State private var totalSize = ""
    private var shelf: Shelf { controller.shelf }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                if controller.layout == .grid { grid } else { list }
            }
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            CircleButton(symbol: "chevron.left", label: "Back to the pile") { controller.setExpanded(false) }
            VStack(alignment: .leading, spacing: 1) {
                Text(shelf.name ?? shelf.title.localizedCapitalized)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                if !totalSize.isEmpty {
                    Text(totalSize)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .onTapGesture(count: 2) { controller.promptForName() }
            .help("Double-click to name this shelf")
            Spacer(minLength: 6)
            layoutToggle
            CircleButton(symbol: "chevron.down", label: "Shelf options and actions") { controller.showActionsMenu() }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .task(id: shelf.items.map(\.id)) { totalSize = await ItemFacts.totalSize(of: controller.shelf.items) }
    }

    private var layoutToggle: some View {
        HStack(spacing: 0) {
            ForEach([ShelfLayout.grid, .list], id: \.self) { option in
                let selected = controller.layout == option
                Button { controller.setLayout(option) } label: {
                    Image(systemName: option == .grid ? "square.grid.2x2" : "list.bullet")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(selected ? Color.primary : Color.secondary)
                        .frame(width: 30, height: 26)
                        .background(selected ? Color.primary.opacity(0.12) : .clear, in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(option == .grid ? "Show as grid" : "Show as list")
                .accessibilityLabel(option == .grid ? "Grid" : "List")
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
            ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                ItemTile(item: item,
                         isSelected: controller.selection.contains(item.id),
                         isMissing: controller.missing.contains(item.id))
                    .overlay(alignment: .leading) { insertionLine(vertical: true, visible: controller.reorderIndex == index) }
                    .overlay(alignment: .trailing) {
                        insertionLine(vertical: true, visible: index == shelf.items.count - 1 && controller.reorderIndex == shelf.items.count)
                    }
                    .modifier(DraggableItem(controller: controller, item: item))
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var list: some View {
        VStack(spacing: 2) {
            ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                ItemRow(item: item,
                        isSelected: controller.selection.contains(item.id),
                        isMissing: controller.missing.contains(item.id))
                    .overlay(alignment: .top) { insertionLine(vertical: false, visible: controller.reorderIndex == index) }
                    .overlay(alignment: .bottom) {
                        insertionLine(vertical: false, visible: index == shelf.items.count - 1 && controller.reorderIndex == shelf.items.count)
                    }
                    .modifier(DraggableItem(controller: controller, item: item))
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private func insertionLine(vertical: Bool, visible: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: vertical ? 3 : nil, height: vertical ? nil : 2)
            .padding(vertical ? .vertical : .horizontal, 6)
            .offset(x: vertical ? -4 : 0, y: vertical ? 0 : -2)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        Group {
            if let status = controller.status {
                Text(status.text)
                    .foregroundStyle(status.isError ? Color.orange : Color.secondary)
            } else {
                Text("Drag items out · Space to preview · ⌫ to remove").foregroundStyle(.tertiary)
            }
        }
        .font(.system(size: 10.5))
        .lineLimit(1)
        .truncationMode(.middle)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: 26)
    }
}

/// Reports an item's frame (for reordering) and makes it draggable, clickable and right-clickable.
struct DraggableItem: ViewModifier {
    let controller: ShelfController
    let item: ShelfItem

    func body(content: Content) -> some View {
        content
            .background(GeometryReader { proxy in
                Color.clear.preference(key: RowFramesKey.self, value: [item.id: proxy.frame(in: .named(ShelfView.space))])
            })
            .overlay(
                DragSource(items: { controller.dragItems(startingWith: item.id) },
                           onClick: { controller.click(item.id, modifiers: $0) },
                           onDoubleClick: { controller.open(item) },
                           menu: { controller.menu(for: item) },
                           onEnded: { controller.didDragOut(ids: $0, operation: $1, at: $2) })
            )
    }
}

struct ItemTile: View {
    let item: ShelfItem
    let isSelected: Bool
    let isMissing: Bool

    var body: some View {
        VStack(spacing: 5) {
            ItemIcon(item: item, size: 72)
                .frame(height: 78)
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
                .overlay(alignment: .topTrailing) {
                    if isMissing {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("This file was moved to the Trash or deleted")
                    }
                }
            Text(item.displayName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isMissing ? .secondary : .primary)
            ItemDetail(item: item)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(isSelected ? Color.accentColor.opacity(0.2) : .clear,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// "347 KB", "187 KB · 3 pages", "Folder", a link's site, or a text's length.
struct ItemDetail: View {
    let item: ShelfItem
    @State private var text = ""

    var body: some View {
        Text(text.isEmpty ? " " : text)
            .lineLimit(1)
            .task(id: item.fileURL) { text = await ItemFacts.describe(item) }
    }
}

enum ItemFacts {
    static func describe(_ item: ShelfItem) async -> String {
        switch item.content {
        case .link(let url):
            return url.host ?? "Link"
        case .text(let text):
            return text.count == 1 ? "1 character" : "\(text.count) characters"
        case .file(let url):
            return await Task.detached(priority: .utility) {
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
                if values?.isDirectory == true { return "Folder" }
                var parts: [String] = []
                if let size = values?.fileSize { parts.append(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) }
                if url.pathExtension.lowercased() == "pdf", let pages = PDFDocument(url: url)?.pageCount {
                    parts.append(pages == 1 ? "1 page" : "\(pages) pages")
                }
                return parts.joined(separator: " · ")
            }.value
        }
    }

    /// Combined size of the files (folders aren't counted), or "" when there are none.
    static func totalSize(of items: [ShelfItem]) async -> String {
        let urls = items.compactMap(\.fileURL)
        return await Task.detached(priority: .utility) {
            var total: Int64 = 0
            for url in urls {
                if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize { total += Int64(size) }
            }
            return total > 0 ? ByteCountFormatter.string(fromByteCount: total, countStyle: .file) : ""
        }.value
    }
}

/// Collects each row's frame so the controller can turn a drop point into a list position.
struct RowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

struct ItemRow: View {
    let item: ShelfItem
    let isSelected: Bool
    let isMissing: Bool

    var body: some View {
        HStack(spacing: 8) {
            ItemIcon(item: item, size: 24)
            Text(item.displayName)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isMissing ? .secondary : .primary)
            Spacer(minLength: 4)
            ItemDetail(item: item)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize()
            if isMissing {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("This file was moved to the Trash or deleted")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(isSelected ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A file's real thumbnail (via Quick Look) once it loads, its Finder icon until then,
/// and a symbol for links and text.
struct ItemIcon: View {
    let item: ShelfItem
    let size: CGFloat
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            switch item.content {
            case .file(let url):
                Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .task(id: url) { thumbnail = await Self.thumbnail(for: url, size: size) }
            case .link:
                symbol("link")
            case .text:
                symbol("text.alignleft")
            }
        }
        .frame(width: size, height: size)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: size * 0.45))
            .foregroundStyle(.secondary)
            .frame(width: size, height: size)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private static func thumbnail(for url: URL, size: CGFloat) async -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: size, height: size),
                                                   scale: scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).nsImage
    }
}

/// Drop targets for Instant Actions, shown along the bottom of a shelf during a drag.
struct InstantActionStrip: View {
    @ObservedObject var controller: ShelfController
    /// Smaller targets for the compact shelf.
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 4 : 6) {
            ForEach(InstantAction.allCases) { action in
                let isHovered = controller.hoveredInstant == action
                VStack(spacing: 3) {
                    Image(systemName: action.symbol).font(.system(size: 15, weight: .medium))
                    Text(action.title).font(.system(size: compact ? 9 : 10, weight: .medium))
                }
                .foregroundStyle(isHovered ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: compact ? 46 : 50)
                .background(isHovered ? Color.accentColor : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(InstantDropZone(action: action, controller: controller))
                .help(action.help)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(action.help)
            }
        }
        .padding(8)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .padding(6)
    }
}

/// One Instant Action target. Plain AppKit so it can take drops directly.
struct InstantDropZone: NSViewRepresentable {
    let action: InstantAction
    let controller: ShelfController

    func makeNSView(context: Context) -> InstantDropZoneView {
        let view = InstantDropZoneView()
        view.registerForDraggedTypes(DropReader.acceptedTypes)
        return view
    }

    func updateNSView(_ view: InstantDropZoneView, context: Context) {
        view.action = action
        view.controller = controller
    }
}

final class InstantDropZoneView: NSView {
    var action: InstantAction = .zip
    weak var controller: ShelfController?

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        // Moving from the shelf onto a zone ends the shelf's own drag session; keep the strip up.
        controller?.isDropTargeted = true
        controller?.hoveredInstant = action
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        // If the pointer goes back onto the shelf, the shelf's draggingEntered turns this on again.
        if controller?.hoveredInstant == action { controller?.hoveredInstant = nil }
        controller?.isDropTargeted = false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let controller else { return false }
        let action = self.action
        controller.hoveredInstant = nil
        controller.isDropTargeted = false
        return DropReader.read(sender.draggingPasteboard) { [weak controller] items in
            controller?.runInstant(action, on: items)
        }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        controller?.hoveredInstant = nil
        controller?.isDropTargeted = false
    }
}
