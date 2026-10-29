# Hoverbox — Product plan

Status: **plan only, nothing built yet** (written 2026-10-27). Publisher: Arcova. App ID `com.arcova.hoverbox`.

A free, open-source drag-and-drop shelf for **macOS and Windows**. Shake the cursor while dragging and a small shelf appears; drop things on it, go wherever you need, then drag them all back out. MIT licensed.

## Name: Hoverbox
Chosen 2026-10-28. A box that hovers above your windows and holds your files until you need them. That is exactly what the shelf is: it floats over every app, appears when you shake mid-drag, and keeps what you drop on it until you drag it back out. The name reads the same on Mac and Windows, is easy to say and spell, and sits next to **Tuck** as a plain, physical word. Icon idea: a rounded box floating slightly above a soft shadow, with one or two file cards peeking out. Tagline idea: "A box that hovers, holding what you drag."

**Clash check, 2026-10-28:** no Mac App Store, iOS App Store or GitHub (macOS) app is named Hoverbox. Still to do before any public release: a trademark search (USPTO, EUIPO, India), a Microsoft Store search, and domain/handle availability (hoverbox.app, @hoverbox).

Names rejected because they're taken: Ledge (a Mac clipboard app), Ferry, Perch ("Perch – Drag & Drop Shelf"), Satchel ("Satchel — File Shelf & Palette"), ShelfDrop, Airlock, Relay, Cubby, Jiggle, Caddy, Sling, Droplet, Limbo, Interlude. Clear backups: Midair, Stepstone, Stagebox, Holdall, Stowaway. Avoid anything that sounds like "Drop…over".

## The technique (same as Tuck and Inkly)
1. **Clean room.** Inspired by the category (Dropover, Yoink and others) but shares no code, name, wording or artwork. Behavior is written from the public App Store listing, the public docs, normal use and the REA findings below. No redistributing paid binaries.
2. **Spec first.** PRODUCT.md (this file), then DESIGN.md, then code.
3. **REA as a scout, not a copier.** REA (Reverse Engineer Anything) is an MCP server that inspects apps without their source, using Hopper/Ghidra for native binaries. On a copy of Dropover we bought, we use it only to answer the "Risks to spike first" questions from the app's **outside**:
   - Info.plist and entitlements: is it sandboxed, which permissions does it ask for (Accessibility, Input Monitoring, Screen Recording)?
   - Linked frameworks and imported system API names (for example `NSEvent addGlobalMonitorForEvents`, `NSPasteboardNameDrag`, `CGEventTap`): which macOS mechanism it uses to sense a drag and a shake.
   - Its runtime behavior while dragging, watched as a user.
   One person writes the findings up as a plain behavior note in `docs/research/dropover.md`. **No decompiled code, pseudocode or assets** go into the repo or into a prompt that writes Hoverbox code. We then build from Apple's docs.
   Caution: Dropover's license (Apple's standard EULA) forbids decompiling or disassembling the app. Going past metadata and imported symbols carries legal risk, and doing so would also break the clean-room claim. If a question can't be answered from the outside, answer it with our own spike instead.
   REA's legitimate deep use: inspecting Apple's own system frameworks and open-source shelf apps where their licenses allow it.
3. **Local and private.** No accounts, no telemetry, no paid tier: every feature is free. Network only for uploads the user turns on.
4. **Native Swift.** Reuse what worked in Tuck.

## How the six repos are used
| Repo | Used for |
|---|---|
| REA (github.com/morluto/rea) | Reverse-engineering MCP (`npx rea-agents setup`). Phase 0 scouting of Dropover's entitlements, frameworks and API imports, within the limits in "The technique" |
| Taste Skill (github.com/Leonxlnx/taste-skill) | Design guardrails while building the shelf UI and the website, so it doesn't look generic |
| Awesome DESIGN.md (github.com/VoltAgent/awesome-design-md) | Format and examples for Hoverbox's DESIGN.md, which agents read |
| Impeccable (github.com/pbakaus/impeccable) | Design review and polish passes: spacing, type, motion, dark mode |
| Playwright CLI (github.com/microsoft/playwright-cli) | Test the website and capture its screenshots (it can't drive the native app; XCUITest does that) |
| img2threejs (github.com/img2threejs/img2threejs) | Turn the icon into a 3D hero for the website |

## Features
The full list is in [FEATURES.md](FEATURES.md): 73 features covering everything in Dropover's free and Pro tiers, the best of Yoink, Dropzone, NotchNook and Perch, plus extras, **all free**. There's no trial, no nag delay and no paid tier. Uploads go to the user's own cloud, never a Hoverbox server. Phase 1 (MVP) has 20 features, Phase 2 has 27 and Phase 3 has 26.

Out of scope: a hosted Hoverbox cloud, accounts, an iOS app, analytics.

## Technical direction
- Swift, SwiftUI views, AppKit `NSPanel` (non-activating, floating, every Space) for shelves; macOS 14+.
- **Drag detection:** a global `NSEvent` monitor for `.leftMouseDragged`, plus the change count of `NSPasteboard(name: .drag)` to confirm a real drag is happening. Watch the cursor path for direction changes in a short window; 3 or more reversals within about 500 ms counts as a shake. This needs no Accessibility permission (confirm this in a spike first).
- Shelf drop and drag-out: `NSDraggingDestination` / `NSDraggingSource` with `NSFilePromiseProvider` for created files.
- File references: security-scoped bookmarks, so pinned shelves survive restarts and the Mac App Store sandbox.
- Images: ImageIO / Core Image. Zip: `Archive` via `NSFileCoordinator` or Apple Archive.
- Hotkey: KeyboardShortcuts (MIT), as in Tuck.
- Project layout copied from Tuck: XcodeGen `project.yml`, `Packages/HoverboxCore` (shake detector, shelf model, rules) with XCTest, XCUITest for shelf flows.
- Distribution: GitHub Releases (signed and notarized), Homebrew cask, then the Mac App Store.

## Windows (same layout as Tuck)
There are two native apps, not one cross-platform UI. Each feels at home on its own OS. They share the same behavior spec, DESIGN.md tokens and test cases.
- Folder `Windows/` with `src/Hoverbox.Core` (shake detector, shelf model, rules; no UI, unit-tested), `src/Hoverbox.App` and `tests/Hoverbox.Core.Tests`, as in Tuck.
- C# / .NET 8, WinUI 3 (Mica material, light/dark); Windows 10 22H2 and Windows 11.
- **Drag detection:** a low-level mouse hook (`SetWindowsHookEx` with `WH_MOUSE_LL`) tracks the path while the left button is held. Treat it as a drag once the pointer has moved past the system drag threshold (`SM_CXDRAG`). Use the same shake rule as on the Mac (direction reversals in a short window). Windows has no public "a drag is in progress" signal, so this is the main Windows risk.
- Shelf: a topmost, no-activate tool window (`WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE`), OLE `IDropTarget` to accept drops and `DoDragDrop` with `CF_HDROP` / virtual files to drag out.
- Hotkey `RegisterHotKey` (default Alt+Shift+Space), tray icon in place of the menu bar, start at login through the MSIX startup task.
- Actions: share via `DataTransferManager`, zip via `System.IO.Compression`, images via WIC.
- Distribution: signed MSIX on GitHub Releases, winget, then the Microsoft Store.
- Order: the Mac MVP ships first, then Windows reaches the same MVP. Phases 2–3 then ship on both.

## Risks to spike first
1. Shake detection (Perch, MIT, already does this with no permissions; study it first): does it work in every app (Finder, browsers, Photos, Mail) without Accessibility, and without false triggers?
2. Sandboxing: global mouse monitors and drag pasteboard access inside the Mac App Store sandbox.
3. Drag-out of promised files to apps that only accept real file URLs.
4. Windows: can a low-level mouse hook tell a real file drag from a text selection or a window move without false opens? Antivirus and elevated (admin) windows may block or skip the hook.

## Build order (when we have tokens)
0. Check the name. Install REA, scout Dropover (metadata, entitlements, imported APIs) and write docs/research/dropover.md. Write DESIGN.md (Awesome DESIGN.md format, Taste Skill + Impeccable).
1. Spike: a shake detector in HoverboxCore with tests, using the mechanism the research points to.
2. MVP shelf panel: drop in, drag out, Quick Look, multiple shelves, pin.
3. Settings, menu bar, hotkey, excluded apps.
4. Phase 2 actions.
5. Icon, website (img2threejs hero, Playwright screenshots), Mac release.
6. Windows: spike the mouse hook, then the MVP shelf, then a Windows release. Phase 2–3 actions follow on both platforms.

## Success checks
- The shelf appears within 100 ms of a shake, with no false opens during a normal drag
- Idle CPU under 1%; no CPU cost while not dragging
- Pinned shelves come back after a restart with every file still reachable
- A new contributor builds and runs it in under five minutes
