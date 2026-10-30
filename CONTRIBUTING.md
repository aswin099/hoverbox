# Contributing to Hoverbox

Thanks for helping. A few ground rules:

1. **Original work only.** Do not copy code, assets or wording from Dropover, Yoink or any other app, and do not reverse-engineer or redistribute paid binaries. Describe behaviour from public documentation or normal use.
2. **No permissions, no network.** Hoverbox must keep working with no Accessibility, Input Monitoring or Screen Recording permission, and must never make network calls of its own.
3. **Never touch originals.** Actions write new files; only Rename, Move To and the user's own drags may change an original.
4. **Test the core.** Logic that does not need AppKit goes in `Packages/HoverboxCore/Sources/HoverboxCore` with tests in `Packages/HoverboxCore/Tests/HoverboxCoreTests`. Run `swift test --package-path Packages/HoverboxCore` before opening a PR.
5. **Follow DESIGN.md** for UI changes: check light and dark mode, Reduce Motion, VoiceOver labels and keyboard use.
6. **Small PRs.** One change per pull request, with a short description of what and why.

## Setup
```sh
brew install xcodegen
xcodegen generate
open Hoverbox.xcodeproj
```

## Issues and pull requests
- Use the **Bug report** or **Feature request** form when opening an issue.
- Open pull requests against `develop`. The pull request template has a short checklist.
- Report security problems privately, as described in [SECURITY.md](SECURITY.md).
- Everyone taking part follows the [code of conduct](CODE_OF_CONDUCT.md).

## Commit messages
Short imperative summary on the first line, details after a blank line if needed.
