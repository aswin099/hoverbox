import AppKit
import Combine
import HoverboxCore
import KeyboardShortcuts
import SwiftUI

/// The menu bar icon. It's AppKit rather than SwiftUI's MenuBarExtra so it can
/// also be a drop target: dropping onto it opens a new shelf below the icon.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let model: AppModel
    private var observation: AnyCancellable?
    private var settingsWindow: NSWindow?

    init(model: AppModel) {
        self.model = model
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.setAccessibilityLabel("Hoverbox")
        statusItem.button?.toolTip = "Hoverbox: drop files here for a new shelf"
        // NSWindow forwards drag-and-drop to its delegate when no view inside takes it.
        statusItem.button?.window?.registerForDraggedTypes(DropReader.acceptedTypes)
        statusItem.button?.window?.delegate = self
        updateIcon()
        observation = model.$isShakePaused.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateIcon() }
        }
    }

    private func updateIcon() {
        let name = model.isShakePaused ? "shippingbox" : "shippingbox.fill"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Hoverbox")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    /// Just below the menu bar icon, for shelves created from it.
    private var pointBelowIcon: NSPoint {
        guard let button = statusItem.button, let window = button.window else { return NSEvent.mouseLocation }
        let frame = window.convertToScreen(button.convert(button.bounds, to: nil))
        return NSPoint(x: frame.midX, y: frame.minY - ShelfPanel.size.height / 2 - 6)
    }

    // MARK: Menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let newShelf = ActionMenuItem("New Shelf") { [weak self] in
            guard let self else { return }
            model.newShelf(at: pointBelowIcon)
        }
        newShelf.setShortcut(for: .newShelf)
        menu.addItem(newShelf)

        if !model.shelves.isEmpty {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem.sectionHeader(title: "Open Shelves"))
            for controller in model.shelves {
                let item = ActionMenuItem(controller.shelf.title) { controller.bringToFront() }
                if controller.shelf.isPinned {
                    item.image = NSImage(systemSymbolName: "pin.fill", accessibilityDescription: "Pinned")
                }
                menu.addItem(item)
            }
            let closeAll = ActionMenuItem("Close Unpinned Shelves") { [weak self] in self?.model.closeUnpinnedShelves() }
            closeAll.isEnabled = model.shelves.contains { !$0.shelf.isPinned }
            menu.addItem(closeAll)
        }

        menu.addItem(.separator())
        let pause = ActionMenuItem("Pause Shake to Open") { [weak self] in self?.model.isShakePaused.toggle() }
        pause.state = model.isShakePaused ? .on : .off
        menu.addItem(pause)

        menu.addItem(.separator())
        let settings = ActionMenuItem("Settings…") { [weak self] in self?.showSettings() }
        settings.keyEquivalent = ","
        menu.addItem(settings)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Hoverbox", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView()))
            window.title = "Hoverbox Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Dropping onto the icon

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        statusItem.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(false)
    }

    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(false)
        let point = pointBelowIcon
        var shelf: ShelfController?
        return DropReader.read(sender.draggingPasteboard) { [weak self] items in
            guard let self else { return }
            // Promised files arrive one by one; they all go on the same new shelf.
            if let shelf, model.shelves.contains(where: { $0 === shelf }) {
                shelf.add(items)
            } else {
                shelf = model.newShelf(at: point, items: items)
            }
        }
    }
}
