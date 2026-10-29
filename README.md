# Hoverbox

A free, open-source drag-and-drop shelf for macOS (Windows to follow). Shake the pointer while dragging and a shelf appears. Drop things on it, go wherever you need, then drag them back out. No permissions, no account, no internet. MIT licensed, by Arcova.

**Status: preview 0.3.0** (Phase 1 done, most of Phase 2 done). See [PRODUCT.md](PRODUCT.md) for the plan and [FEATURES.md](FEATURES.md) for the full feature list.

## What works in the preview
- **Two faces:** a shelf appears compact, as a pile of thumbnails with its name. Drag the pile to take everything; click it or the name to grow it into the full view, a grid or list with names, sizes and PDF page counts. The chevron opens shelf options (pin, name, show all) and the actions.
- **Shake to open:** shake the pointer while dragging anything (files, images, links, text) and a shelf appears under it. Asks for no permissions.
- **Hotkey:** ⌥⇧Space opens a shelf at the pointer. Change it in Settings.
- **Drop anything:** files and folders, images from a browser, photos from Photos, links, and text.
- **Drag out:** drag the pile at the top to move everything, or drag single items. Select with click, ⌘-click or Shift-click and drag the selection. In Finder, Option copies and Command moves.
- **After dragging out**, items leave the shelf and an empty shelf closes. Hold Shift as you drop, pin the shelf, or turn on "Keep items" in Settings to keep them.
- **Drop onto the menu bar icon** to get a new shelf just below it.
- **Multiple shelves.** Move one by dragging any empty part of it (the grabber bar at the top shows where); double-click an empty part to name it. Drag items within a shelf to reorder them; drag them onto another shelf to move them there.
- **Colours:** give a shelf a colour from the chevron menu; it tints the grabber and shows in the menu bar list.
- **Dock to an edge:** push a shelf against the left or right edge of the screen and it tucks away as a slim tab. Click the tab, or drag files over it, to bring it back.
- **Recently Closed:** the menu bar keeps the last 10 shelves you closed with things on them; pick one to reopen it.
- **Favourites:** add folders and apps in Settings. While you drag over a shelf they appear as drop targets under the Instant Actions (folders get a copy, ⌘ moves; apps open the files), and in the shelf menu as Copy To, Move To and Open With.
- **Automatic shelves:** new screenshots (recognised by the marker macOS writes on them, in any language) and new files in watched folders such as Downloads appear on a named shelf in the top-right corner, without taking focus. Unfinished downloads are ignored.
- **Pin** a shelf to keep it with its items after restarting. Pinned shelves follow files that get renamed or moved, and flag ones that were deleted.
- **Keys:** Space opens Quick Look, ↑/↓ move the selection (Shift extends it), Return opens, ⌫ removes, ⌘A selects all, Esc clears the selection. Double-click opens an item; double-click the title to rename the shelf.
- **Right-click** an item: Open, Quick Look, Show in Finder, Rename… (renames the file itself), Copy, Remove.
- **Actions** (the ⚡ button acts on the selection, or the whole shelf; also in the right-click menu): Share, AirDrop, Compress to ZIP, Unzip, Resize Images (25/50/75% or longest side 800–3840 px), Convert Images To PNG/JPEG/HEIC/TIFF, Compress Images (keeps a result only if it's smaller), Extract Text (images and PDFs, copied to the clipboard). Results are new files added to the shelf and selected; originals are never changed. Image metadata such as location isn't copied into results.
- **Instant Actions:** while you drag over a shelf, a strip appears at the bottom: drop on AirDrop, Share, ZIP or Text to run it straight away without collecting first.
- **Accessibility:** VoiceOver labels on every control, full keyboard use, and Reduce Motion respected.
- **Menu bar:** new shelf, open shelves, close unpinned shelves, pause shake, Settings.
- **Settings:** shelf background from glass to solid (live), shake on/off and sensitivity, hotkey, keep after drag-out, apps where shaking is ignored, launch at login.
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
