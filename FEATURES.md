# Hoverbox — Feature list

Everything Dropover offers, free and Pro, plus what it lacks, **all free in Hoverbox**: no trial, no nag delay, no paid tier. Written 2026-10-28 from Dropover's public App Store listing (v5.3.1), its website and its FAQ, in our own words.

**Built so far (2026-10-28):** all of Phase 1 except 7.6 (updates, decided at release); from Phase 2: 1.9, 1.11, 1.12, 1.13, 1.14 (copy), 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 5.1, 5.2, 8.4, 8.5, 8.6, 8.8. Also: 1.14 paste, 2.8 Finder Services (with a shortcut), and accessibility additions (hold still to open, VoiceOver announcements). Still open in Phase 2: 1.17, 2.7, 2.9, 7.2, 7.3, 8.2, 8.3, 8.10.

## What Dropover charges for (and what we do instead)
| Dropover | Hoverbox |
|---|---|
| 14-day trial, then a 3-second wait before every shelf can be used | Never any delay or trial |
| Pro: $7.99 one-time to remove the wait | Free, MIT open source |
| Pro-flavored extras: Shortcuts, watched folders, Share Extension, Command Bar | All included |
| Dropover Cloud: 1 GB free, 10 GB Pro, on their servers | **No Hoverbox server.** Free uploads to the user's own iCloud Drive, Dropbox, Google Drive, OneDrive, S3 / R2 / any S3-compatible storage, Imgur, or a local folder they share themselves |
| Mac only | Mac **and Windows** |
| Collects usage data, identifiers and diagnostics | No analytics, no IDs, no network unless the user uploads |

Phase: **1** = MVP, **2** = actions and integrations, **3** = power and polish. "Win" = the Windows equivalent.

## 1. Shelves
| # | Feature | Phase | Win |
|---|---|---|---|
| 1.1 | Floating shelf that holds files, folders, images, links, text, and web images dragged from a browser | 1 | Same |
| 1.2 | Shelf holds **references**, not copies; handles files that are later moved, renamed or deleted (tracked by bookmark, marked missing if gone) | 1 | File IDs |
| 1.3 | Drag everything out at once, or single or selected items | 1 | Same |
| 1.4 | Quick Look preview (Space) | 1 | Preview pane / built-in viewer |
| 1.5 | Rename, reorder and remove items on a shelf | 1 | Same |
| 1.6 | Multiple shelves at once | 1 | Same |
| 1.7 | Shelves don't steal focus when they appear | 1 | `WS_EX_NOACTIVATE` |
| 1.8 | Choose: close the shelf after dragging out, or keep it open; hold Shift while dragging to keep it open for that drag | 1 | Same |
| 1.9 | Name and color-code shelves | 2 | Same |
| 1.10 | Pin shelves (they survive restarts) | 1 | Same |
| 1.11 | Reopen recently closed shelves (last 10, configurable) | 2 | Same |
| 1.12 | Dock shelves to a screen edge as a slim tab, and pull them back out | 2 | Same |
| 1.13 | Detail view: an expanded shelf window that can stay open beside other windows | 2 | Same |
| 1.14 | Copy shelf items to the clipboard; paste the clipboard onto a shelf | 2 | Same |
| 1.15 | Drag messages straight out of Mail (and Outlook on Windows) | 3 | Outlook `.msg` |
| 1.16 | Automatic shelf names from the contents (on-device; can be turned off) | 3 | Rule-based names |
| 1.17 | Low-disk-space warning before actions that write files | 2 | Same |

## 2. Ways to open a shelf
| # | Feature | Phase | Win |
|---|---|---|---|
| 2.1 | Shake the pointer while dragging | 1 | Mouse hook (see PRODUCT.md) |
| 2.2 | Shake sensitivity setting, and turn shake off entirely | 1 | Same |
| 2.3 | Excluded apps (no shake in games, design tools and so on) | 1 | Same |
| 2.4 | Global hotkey for a new shelf | 1 | `RegisterHotKey` |
| 2.5 | Drop onto the menu bar icon | 1 | Tray icon |
| 2.6 | Drop onto the MacBook notch | 3 | n/a |
| 2.7 | Global shortcut to pick between open shelves | 2 | Same |
| 2.8 | Right-click "Add to Hoverbox" in Finder (Services) | 2 | Explorer context menu |
| 2.9 | Share Extension: "Hoverbox" in any app's Share menu | 2 | Windows share target |

## 3. Actions on shelf items
| # | Feature | Phase | Win |
|---|---|---|---|
| 3.1 | Share via the system Share menu, AirDrop, Mail, Messages | 2 | Windows Share, Nearby Share |
| 3.2 | Create a ZIP | 2 | Same |
| 3.3 | Resize images | 2 | WIC |
| 3.4 | Convert images (PNG, JPEG, HEIC, TIFF; WebP output needs a bundled encoder, as macOS ImageIO only reads WebP) | 2 | WIC |
| 3.5 | Extract text from images and PDFs (on-device OCR) | 2 | `Windows.Media.Ocr` |
| 3.6 | Copy, move to, or reveal in a chosen folder | 2 | Same |
| 3.7 | **Instant Actions:** drop files straight onto an action (zip, convert, upload, share) without collecting them first | 2 | Same |
| 3.8 | Action suggestions: hold Option to repeat recent actions | 3 | Alt |
| 3.9 | Command Bar: type to find and run any action | 3 | Same |
| 3.10 | Choose which actions show in the main menu and which go in a submenu | 3 | Same |
| 3.11 | Extras Dropover doesn't have: strip image metadata, batch rename with a pattern, merge images or PDFs into one PDF | 3 | Same |

## 4. Uploads and links (user's own storage, no Hoverbox server)
| # | Feature | Phase | Win |
|---|---|---|---|
| 4.1 | One click: upload and copy a share link | 3 | Same |
| 4.2 | Providers: iCloud Drive, Dropbox, Google Drive, OneDrive, Amazon S3 and S3-compatible (Cloudflare R2, Backblaze B2, MinIO), Imgur | 3 | iCloud for Windows; others the same |
| 4.3 | Upload options where the provider supports them: link expiry, password (S3 pre-signed links, Dropbox/Drive link settings) | 3 | Same |
| 4.4 | Upload history with copy link / delete, in the menu bar and Settings | 3 | Tray |
| 4.5 | Credentials stored in the Keychain / Windows Credential Manager only | 3 | Same |

## 5. Automation and integrations
| # | Feature | Phase | Win |
|---|---|---|---|
| 5.1 | Watched folders: new files in a folder auto-open a shelf | 2 | `FileSystemWatcher` |
| 5.2 | New screenshots go to a shelf automatically | 2 | Snipping Tool folder watch |
| 5.3 | Custom actions built from steps (for example resize, then zip, then upload) | 3 | Same |
| 5.4 | Custom scripts: shell, AppleScript, Automator | 3 | PowerShell, cmd |
| 5.5 | Apple Shortcuts actions: add to a shelf, upload, get shelf items | 3 | CLI + `hoverbox://` URL scheme |
| 5.6 | Alfred and Raycast extensions | 3 | PowerToys Run plugin |
| 5.7 | `hoverbox` command-line tool (add files, open a shelf, list shelves) | 3 | Same |

## 6. System surfaces
| # | Feature | Phase | Win |
|---|---|---|---|
| 6.1 | Menu bar item: shelves, pause shake, settings | 1 | Tray icon |
| 6.2 | Desktop widgets showing recent shelves | 3 | Windows widget board |
| 6.3 | Control Center controls (new shelf, pause shake) | 3 | Tray quick menu |
| 6.4 | Spotlight: find pinned shelves | 3 | n/a |

## 7. Settings and app basics
| # | Feature | Phase | Win |
|---|---|---|---|
| 7.1 | Launch at login | 1 | MSIX startup task |
| 7.2 | Customizable shortcuts for every action | 2 | Same |
| 7.3 | Shelf appearance: size, position, light/dark/auto, compact or grid | 2 | Same |
| 7.4 | Languages: start with English; add Dutch, German, Spanish, Italian, Simplified Chinese, then Hindi and Malayalam | 3 | Same |
| 7.5 | Accessibility: full VoiceOver / Narrator labels, keyboard-only use, reduced motion | 1 | Same |
| 7.6 | Updates: App Store / Microsoft Store, or Sparkle / winget for direct downloads | 1 | winget |
| 7.7 | Privacy: no analytics; optional crash reports only if the user turns them on | 1 | Same |

## 8. Ideas from other competitors (researched 2026-10-28)
Competitors: **Yoink** (Mac, $8.99 one-time or Setapp), **Dropzone 4** (Mac, $1.99/month or $35 lifetime; Pro needed for S3/FTP, action shortcuts and its script API), **NotchNook** and **Droppy** (paid notch apps with file trays), **Perch by hausfold** (Mac, MIT open source, notch shelf), **Dockside** (paid shelf beside the Dock). On Windows: **Dropshelf** (freemium, about €4 Pro), **Tokri** and **Droper** (MIT, cross-platform, basic), **DropPoint** (open source, discontinued). No Windows app matches Dropover's depth, which is our opening.

| # | Feature | From | Phase | Win |
|---|---|---|---|---|
| 8.1 | Drag-out modifiers: Option forces a copy, Command forces a move | Yoink | 1 | Ctrl / Shift |
| 8.2 | Shelf placement choice: screen edge, at the cursor, beside the Dock, or the notch | Yoink, Dockside | 2 | Edge, cursor, taskbar |
| 8.3 | Hotkey gestures: long-press to bring back items you dragged out, double-press to put the clipboard on a shelf | Yoink | 2 | Same |
| 8.4 | Favorites grid: drop onto a pinned folder to copy or move there, or onto an app to open with it | Dropzone | 2 | Same |
| 8.5 | Unzip archives on the shelf | NotchNook | 2 | Same |
| 8.6 | Compress images (smaller file size, same format) | NotchNook, Droppy | 2 | Same |
| 8.7 | SFTP, FTP and WebDAV upload targets | Dropzone Pro | 3 | Same |
| 8.8 | AirDrop and Share targets show up as drop zones while dragging | NotchNook, DropNotch | 2 | Nearby Share |
| 8.9 | Continuity Camera: photo or document scan from an iPhone straight onto a shelf | Yoink | 3 | n/a |
| 8.10 | Copy mode: keep copies on the shelf instead of references, so originals are never touched | Perch | 2 | Same |
| 8.11 | Agent support: a CLI skill so coding agents (Claude Code and others) can add to and read shelves | Perch | 3 | Same |
| 8.12 | Works with Tuck: send clipboard items to a shelf and shelf text to Tuck, instead of building a second clipboard history | Yoink, Droppy | 3 | Same |
| 8.13 | Action packages written in Python or JavaScript, shareable as single files | Dropzone Pro | 3 | Same |

Skipped on purpose: music and widget panels (NotchNook, boring.notch), link shortening through a third-party service (Dropzone's TinyURL), and an iOS companion app (Perch, Yoink). Possible later as "Hoverbox Companion".

Engineering note: Perch (github.com/hausfold/perch, MIT) catches drags with **no Accessibility, Input Monitoring or Screen Recording permission**. Read its ARCHITECTURE.md and source (allowed under MIT, keeping its copyright notice for anything reused) before the shake-detection spike. That answers most of risk 1 without REA.

## Count
73 features: 20 in Phase 1 (MVP), 27 in Phase 2, 26 in Phase 3. Every one of them is free.
