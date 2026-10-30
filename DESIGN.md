# Hoverbox — DESIGN.md

Design system for the Hoverbox macOS app (and the Windows app to come), its website page and its README. Format follows the DESIGN.md convention so coding agents can read it.

## 1. Visual theme and atmosphere
A light, friendly tool that floats above your work and gets out of the way. One object, a cardboard box hovering over its own shadow, carries the identity. The shelf itself is quiet glass: it shows your files, not itself. No gradients on the shelf, no glow, no decorative chrome. Motion is short and springy, never bouncy for its own sake.

## 2. Color palette and roles
| Token | Hex | Role |
|---|---|---|
| ocean-900 | #143A5C | App icon tile, website accent, text on light brand surfaces |
| cardboard-300 | #F4B66A | Box front (icon), warm highlights on the website |
| cardboard-500 | #D98E48 | Box side (icon) |
| cardboard-900 | #6E4120 | Inside of the box (icon) |
| coral-400 | #FF6B57 | The single accent dot (icon); never body text |
| sky-100 | #CFEAFF | Photo sky (icon) |

**Shelf colours** (the user picks one per shelf; it tints the grabber, selection, drop outline, drop targets and docked tab): red #FF5A52, orange #FF9F2E, yellow #F5C518, green #3CC35F, mint #34C7B8, blue #3B82F6, purple #9B6BF2, pink #F0619A, graphite #8E8E93. A shelf with no colour uses the system accent. Light colours (luminance above 0.6: yellow, mint) get black text on hovered targets; the rest get white.

**In the app, prefer system colours** (`.primary`, `.secondary`, `.windowBackgroundColor`) so light and dark mode and Increase Contrast work for free. Brand colours live in the icon and the website.

## 3. Typography
- App UI: SF Pro (system font).
- Website: the Arcova site's fonts.

| Role | Size / weight |
|---|---|
| Compact name pill | 13 / semibold |
| Expanded title | 15 / bold, size underneath 11 / regular secondary |
| Grid tile name | 12 / medium, detail 10.5 / regular secondary |
| List row | 13 / regular, size 11 secondary |
| Footer and status | 10.5 / regular, tertiary (errors in orange) |
| Instant Action label | 10 / medium (9 on the compact shelf) |

## 4. Component styling
- **Shelf card**: corner radius 22 (continuous), background is macOS's behind-window blur faded towards the window colour by the Glass ↔ Solid setting, 0.5 pt hairline border, its own soft shadow (blur 12, y 6, 32% black). The window around it is transparent with a 22 pt margin so the shadow can breathe.
- **Compact card**: 216 × 236. Close and chevron as 30 pt round buttons (8% primary fill), grabber centred at the top, a pile of up to three thumbnails (96 pt, fanned −10°, +8°, −1°), and a 32 pt name pill.
- **Expanded card**: 452 × 372 (600 × 480 when Large). Header with back button, title and size, grid/list toggle in a capsule, chevron. Grid of 3 columns (4 when Large) with 72 pt thumbnails; list rows 32 pt.
- **Grabber**: capsule 46 × 3.5 pt (4 pt when coloured), 22% primary or the shelf colour. Purely visual; the whole empty card is the drag handle.
- **Selection**: shelf accent at 20% (tiles) or 18% (rows), radius 12 / 8.
- **Drop outline**: 2 pt in the shelf accent while something is dragged over the shelf.
- **Instant Actions strip**: thick material, radius 14, targets 50 pt tall (46 compact), radius 10, hovered target fills with the shelf accent.
- **Docked tab**: 34 × 120, rounded only on the side facing the screen, colour stripe, item count and a chevron pointing inward.
- **Settings**: native toolbar tabs, grouped forms, two-line toggles (title and explanation), ＋/− lists, every tab 580 × 460 so the window never jumps.

## 5. Layout principles
- 4 pt base grid. Spacing scale: 2, 4, 6, 8, 12, 14, 22.
- The card grows and shrinks around its top centre, so it never shifts sideways.
- New shelves from a drag appear centred on the pointer; others follow the placement setting.

## 6. Depth and motion
- Two levels only: shelves (floating, own shadow) and standard windows (Settings, alerts).
- Expand and collapse: one spring (response 0.36, damping 0.86) on the card size; each face is laid out at its final size and cross-faded (out 0.12–0.14 s, in 0.22 s after a short delay). The window resizes once, never per frame.
- Drop strip: slides up from the bottom with a 0.15 s ease-out.
- With Reduce Motion on, all of these become instant or plain fades.

## 7. Do's and don'ts
Do:
- Show what the files are (real thumbnails), not decoration
- Give every control a VoiceOver label and every action a keyboard path
- Say what happened in the footer ("2 images resized") and announce it to VoiceOver
- Keep originals untouched: actions make new files

Don't:
- Ask for permissions (Accessibility, Input Monitoring, Screen Recording) or reach the network
- Steal focus from the app the user is dragging from
- Copy another app's screens, icons or wording
- Use the brand colours for body text, or the coral accent for anything but the icon dot

## 8. Icons
- App icon: drawn in code by `tools/render-icon.swift` (macOS sizes and Windows `.ico`). Ocean tile, cardboard box with open flaps hovering over its shadow, a photo and a document rising out, one coral dot.
- Menu bar: the system `shippingbox` symbol, filled while active, outlined while paused.
