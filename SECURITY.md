# Security policy

Hoverbox sits between you and your files: it holds references to them, copies them in copy mode, and runs actions on them. Security reports are taken seriously.

## Supported versions

Hoverbox is in early preview. Only the latest release gets security fixes.

| Version | Supported |
|---|---|
| Latest release | Yes |
| Older releases | No |

## Reporting a vulnerability

**Please don't open a public issue for security problems.**

Report privately through GitHub instead: open the repository's **Security** tab and choose **Report a vulnerability**. Only the maintainer can see the report.

Please include:
- What the problem is and what an attacker could do with it
- Steps to reproduce it, and your macOS (or Windows) version and Hoverbox version

Never include private files or real personal file paths in a report. Use made-up examples.

## What to expect

- An acknowledgement within 7 days
- An assessment and, for confirmed issues, a fix or plan as soon as possible
- Credit in the release notes if you'd like it

## In scope

- Files changed, moved or deleted without the user asking (originals must never be touched except by Rename, Move To, or a move the user makes when dragging out)
- Files or shelf contents readable by other users or apps (the shelf archive is written with 0600 permissions)
- `hoverbox://` links or the Share extension being abused to read or move files
- Any network traffic from Hoverbox itself (there should be none; sharing goes through macOS)
- Hoverbox asking for permissions it doesn't need

Out of scope: problems that need an attacker who already controls your user account, and issues in macOS, Windows or third-party apps themselves.
