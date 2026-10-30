# Releasing Hoverbox

Status on 2026-10-29: everything that can be prepared locally is ready. The steps marked **You** need an account, money or a public action.

## 1. Name (done, with one note)
- No registered "Hoverbox" trademark turned up in searches (USPTO, EUIPO and India still worth a direct search before paying for anything).
- Existing uses: **XYplorer** (a Windows file manager) calls a file-preview popup "HoverBox™", and **RapidWeaver** sells a web-design stack called "HoverBox". Neither is a drag-and-drop shelf app, and "hover box" is also a generic UI term, so the risk is low. Avoid "HoverBox" capitalisation to stay distinct; we use "Hoverbox".
- Taken: hoverbox.com (2006), hoverbox.io (2024), the GitHub user "hoverbox". Free: hoverboxapp.com, gethoverbox.com, `aswin099/hoverbox` on GitHub, the Homebrew cask name `hoverbox`. The site lives on GitHub Pages, so no domain is needed.

## 2. GitHub repository (**You**: create it, or approve me creating it)
- Create the public repo `aswin099/hoverbox`, then push `main` (and a `develop` branch, like Tuck).
- Included and ready: `.github/workflows/ci.yml` (tests and build on every push), `.github/workflows/release.yml` (draft release on a `v*` tag), issue forms, PR template, `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md`, `DESIGN.md`, MIT `LICENSE`.
- After the first push: turn on private vulnerability reporting (Settings › Security), and protect `main`.

## 3. Signing and notarization (**You**: decide)
| Option | Cost | Result |
|---|---|---|
| **A. Ad hoc, like Tuck** (works today) | Free | People right-click › Open the first time, or use "Open Anyway". The Share extension may need enabling by hand. |
| **B. Developer ID + notarization** (recommended for a real launch) | Apple Developer Program, US$99/year | Opens on any Mac without warnings; the Share extension and Services register normally. |

For B, add five repository secrets (`DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_APP_PASSWORD`). The release workflow already signs, notarizes and staples when they exist, and falls back to A when they don't. "Inc." in the seller name needs a registered company and a D-U-N-S number; as an individual the seller name is your own.

## 4. Distribution
1. **GitHub Releases** (ready): `git tag v0.4.0 && git push origin v0.4.0` builds `Hoverbox-macOS.zip` and a draft release. Review it, then Publish.
2. **Homebrew cask** (after the first notarized release): a `hoverbox` cask pointing at the release zip.
3. **Updates**: add Sparkle with an appcast on GitHub Pages once releases are signed (it needs a signing key and a stable download URL).
4. **Mac App Store** (later, optional): needs the App Sandbox. Known work: security-scoped bookmarks for shelf items, replacing the `ditto` process for ZIP, and checking that the global mouse monitor and drag pasteboard still work sandboxed.

## 5. Website (**You**: approve publishing)
- Ready in `inkly/website/` (the Arcova site's source): `hoverbox/index.html`, a Hoverbox card and footer link on the home page, `.t-hoverbox` colours in `site.css`, and `img/hoverbox-icon.png` and `img/hoverbox-shelf.png`. Checked at 390 px: no sideways scrolling, all images load.
- Publish by copying the folder into the `aswin099/arcova` clone, committing and pushing. Do this together with creating the GitHub repo, since the page links to its releases.

## 6. Before tagging v0.4.0
- [ ] Hand-test: hold still to open, ⌘V paste, ⇧⌘B in Finder, favourites drop, Share menu, gestures, VoiceOver announcements
- [ ] Update README screenshots if the UI changed
- [ ] `swift test --package-path Packages/HoverboxCore` passes (48 tests today)
- [ ] Remove nothing debug-only by hand: `hoverbox://debug` is compiled out of Release builds
