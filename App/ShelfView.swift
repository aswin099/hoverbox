import HoverboxCore
import QuickLookThumbnailing
import SwiftUI

/// The shelf's contents: a header, a "pile" that drags everything at once,
/// and a list of items that drag one at a time (or as a selection).
struct ShelfView: View {
    @ObservedObject var controller: ShelfController
    @State private var isRenaming = false
    @State private var draftName = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shelf: Shelf { controller.shelf }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.6)
            if shelf.isEmpty {
                emptyState
            } else {
                pile
                Divider().opacity(0.6)
                itemList
                footer
            }
        }
        .frame(width: ShelfPanel.size.width, height: ShelfPanel.size.height)
        .coordinateSpace(name: ShelfView.space)
        .onPreferenceChange(RowFramesKey.self) { controller.rowFrames = $0 }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(controller.isDropTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                              lineWidth: controller.isDropTargeted ? 2 : 0.5)
        )
        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: controller.isDropTargeted)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Shelf: \(shelf.title)")
    }

    static let space = "shelf"

    private var header: some View {
        HStack(spacing: 8) {
            if isRenaming {
                TextField("Shelf name", text: $draftName)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .semibold))
                    .onSubmit {
                        controller.rename(to: draftName)
                        isRenaming = false
                    }
                    .onExitCommand { isRenaming = false }
            } else {
                Text(shelf.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .onTapGesture(count: 2) {
                        draftName = shelf.name ?? ""
                        isRenaming = true
                        controller.panel.makeKey()
                    }
                    .help("Double-click to rename")
            }
            Spacer(minLength: 4)
            Button { controller.togglePin() } label: {
                Image(systemName: shelf.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(shelf.isPinned ? Color.accentColor : .secondary)
            }
            .help(shelf.isPinned ? "Unpin shelf" : "Pin shelf: keep it and its items after dragging out and after restarting")
            .accessibilityLabel(shelf.isPinned ? "Unpin shelf" : "Pin shelf")
            Button { controller.close() } label: {
                Image(systemName: "xmark").foregroundStyle(.secondary)
            }
            .help("Close shelf")
            .accessibilityLabel("Close shelf")
        }
        .buttonStyle(.plain)
        .font(.system(size: 12))
        .padding(.horizontal, 12)
        .frame(height: 34)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(controller.isDropTargeted ? Color.accentColor : .secondary)
            Text("Drop files here")
                .font(.system(size: 13, weight: .medium))
            Text("Then drag them out wherever you need them.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundStyle(Color.secondary.opacity(0.5))
        )
        .padding(12)
    }

    /// Up to three items fanned out, with a count; dragging it takes everything.
    private var pile: some View {
        let shown = Array(shelf.items.prefix(3))
        return VStack(spacing: 6) {
            ZStack {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    ItemIcon(item: item, size: 56)
                        .rotationEffect(.degrees(Double(index - (shown.count - 1) / 2) * 7))
                        .offset(x: CGFloat(index) * 10 - CGFloat(shown.count - 1) * 5)
                        .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                }
            }
            .frame(height: 62)
            .overlay(alignment: .topTrailing) {
                Text("\(shelf.items.count)")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: 14, y: -4)
            }
            Text(shelf.items.count == 1 ? "Drag to move it" : "Drag to move all \(shelf.items.count)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 100)
        .contentShape(Rectangle())
        .overlay(
            DragSource(items: { controller.shelf.items },
                       onEnded: { controller.didDragOut(ids: $0, operation: $1, at: $2) })
        )
        .help("Drag to move everything on this shelf")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Drag all \(shelf.items.count) items")
    }

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 2) {
                ForEach(Array(shelf.items.enumerated()), id: \.element.id) { index, item in
                    ItemRow(item: item,
                            isSelected: controller.selection.contains(item.id),
                            isMissing: controller.missing.contains(item.id))
                        .overlay(alignment: .top) { insertionLine(visible: controller.reorderIndex == index, offset: -2) }
                        .overlay(alignment: .bottom) {
                            insertionLine(visible: index == shelf.items.count - 1 && controller.reorderIndex == shelf.items.count,
                                          offset: 2)
                        }
                        .background(GeometryReader { proxy in
                            Color.clear.preference(key: RowFramesKey.self,
                                                   value: [item.id: proxy.frame(in: .named(ShelfView.space))])
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
            .padding(6)
        }
    }

    private func insertionLine(visible: Bool, offset: CGFloat) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: 2)
            .padding(.horizontal, 4)
            .offset(y: offset)
            .opacity(visible ? 1 : 0)
            .accessibilityHidden(true)
    }

    private var footer: some View {
        Text("Space to preview · ⌫ to remove")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity)
            .frame(height: 22)
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
            Spacer(minLength: 0)
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
