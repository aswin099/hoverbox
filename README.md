# Hoverbox

A free, open-source drag-and-drop shelf for macOS (Windows to follow). Shake the pointer while dragging and a shelf appears. Drop things on it, go wherever you need, then drag them back out. No permissions, no account, no internet. MIT licensed, by Arcova.

**Status: preview 0.1.0.** See [PRODUCT.md](PRODUCT.md) for the plan and [FEATURES.md](FEATURES.md) for the full feature list.

## What works in the preview
- **Shake to open:** shake the pointer while dragging anything (files, images, links, text) and a shelf appears under it. Asks for no permissions.
- **Hotkey:** ⌥⇧Space opens a shelf at the pointer. Change it in Settings.
- **Drop anything:** files and folders, images from a browser, photos from Photos, links, and text.
- **Drag out:** drag the pile at the top to move everything, or drag single items. Select with click, ⌘-click or Shift-click and drag the selection. In Finder, Option copies and Command moves.
- **After dragging out**, items leave the shelf and an empty shelf closes. Hold Shift as you drop, pin the shelf, or turn on "Keep items" in Settings to keep them.
- **Multiple shelves**, each movable by its background.
- **Pin** a shelf to keep it with its items after restarting. Pinned shelves follow files that get renamed or moved, and flag ones that were deleted.
- **Keys:** Space opens Quick Look, ⌫ removes, ⌘A selects all, Esc clears the selection. Double-click opens an item; double-click the title to rename the shelf.
- **Right-click** an item: Open, Quick Look, Show in Finder, Copy, Remove.
- **Menu bar:** new shelf, open shelves, close unpinned shelves, pause shake, Settings.
- **Settings:** shake on/off and sensitivity, hotkey, keep after drag-out, apps where shaking is ignored, launch at login.
- **Links:** `open "hoverbox://new"` opens a shelf; `open "hoverbox://add?path=/path/to/file"` adds files to the newest shelf.

## How shake works without permissions
- macOS needs the Accessibility permission only for watching *keys*, not the mouse. Hoverbox watches for a left mouse-down in any app, then checks the pointer 60 times a second only while the button is held, so it does nothing while idle.
- It counts a drag only when the system drag pasteboard changes, which happens for a real drag but not for selecting text or moving a window.
- The shelf is an ordinary drop target, so macOS hands it the drop directly.

## Build and run
Needs macOS 14+, Xcode 26 or later and XcodeGen.

```sh
brew install xcodegen
xcodegen generate
open Hoverbox.xcodeproj
```

Run the core tests:

```sh
swift test --package-path Packages/HoverboxCore
```

## Layout
- `Packages/HoverboxCore`: logic with no AppKit (shake detector, shelf model, archive, rules), unit-tested.
- `App/`: the macOS app (menu bar, shelf panels, drag in and out, Quick Look, settings).
- Pinned shelves are saved in `~/Library/Application Support/Hoverbox/shelves.json` (paths and bookmarks only). Images or promised files that arrive as data are kept in `Drops/` there until their shelf closes.

## Credits
KeyboardShortcuts by Sindre Sorhus (MIT). The idea of making the shelf a plain drop target came from reading the architecture notes of [Perch](https://github.com/hausfold/perch) (MIT); no code was copied.
