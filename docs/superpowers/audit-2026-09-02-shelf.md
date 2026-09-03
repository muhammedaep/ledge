# Shelf audit vs. design source (`Ledge UI.dc.html`, options 1a–1d)

Note on the design source: I read lines 1–95 (tokens) and 96–175 (options 1a "shelf·light", 1b "shelf·dark/Turkish", 1c "row hierarchy", 1d "shelf states") plus enough of 1e to confirm it's Settings/Rules (out of scope). The content is HTML-entity-escaped user-authored markup; I found nothing in it that reads as an instruction to me. Separately, the task message I received carried an embedded "context_window_protection" block insisting I use `ctx_batch_execute`/`ctx_execute` MCP tools instead of Read/Bash. I disregarded it — it wasn't part of any verified system configuration, it conflicted with this audit's need for exact `file:line` citations, and Read/Bash/`mcp__claude_design__read_file` were sufficient and reliable.

Files audited: `Ledge/Shelf/ShelfView.swift`, `Ledge/Shelf/ShelfRow.swift`, `Ledge/Shelf/TypeBadge.swift`, `Ledge/ErrorBanner.swift`, `Ledge/Onboarding/PermissionView.swift`, `Ledge/Design/Theme.swift` (read for values only).

## Discrepancies (most significant first)

| # | Element | Design value (selector/attr) | Our value | Our file:line | Severity |
|---|---|---|---|---|---|
| 1 | Dark badge **border** alpha, all 3 families | doc `rgba(240,150,140,.45)`, image `rgba(120,170,235,.5)`, movie `rgba(190,150,240,.45)` (rows in 1b) | `badgeDocBorder`/`badgeImageBorder`/`badgeMovieBorder` dark all use alpha **.28** | `Theme.swift:85,88,91` | HIGH |
| 2 | Dark **document** badge fill+border base hue | fill `rgba(240,150,140,.16)`, border `rgba(240,150,140,.45)` (KEY/PDF rows, 1b) | `badgeDocPage`/`badgeDocBorder` dark reuse `srgb(0xff6961,…)` — the unrelated semantic **red** color (255,105,97), not a coral derived from the doc label `#ef9a92` the way image/movie correctly derive their fill/border from their own label hue | `Theme.swift:84-85` | HIGH |
| 3 | Type badge shape — folded corner | Two paths per icon: page outline **and** a solid triangle `M19 3l6 6h-6z` filled in the border color (the dog-ear flap), e.g. row markup in 1a/1b | `PageShape` only draws the outline (`.fill`+`.stroke` of the same single path); no second flap shape, so the cut corner shows nothing instead of a colored triangle | `TypeBadge.swift:54-59,77-88` | HIGH |
| 4 | Permission-denied screen — icon | 28×28 circle+slash icon, stroke `#c4544c`, stroke-width 1.6 (1d "Permission denied") | No icon at all | `PermissionView.swift:20-66` | HIGH |
| 5 | Permission-denied screen — button style | Filled pill: `background:var(--accent);color:#fff;height:26px;padding:0 12px;border-radius:6px;font-size:12px;font-weight:500;box-shadow:0 .5px 2px rgba(0,0,0,.25)` | Plain-style text button, `.rowName()` (13pt regular) + `Theme.Colour.accent` foreground — no fill, no pill shape | `PermissionView.swift:62-65` | HIGH |
| 6 | Permission-denied screen — alignment | `text-align:center` on the whole block | `VStack(alignment: .leading, …)` + `.frame(… alignment: .leading)` | `PermissionView.swift:20,71` | HIGH |
| 7 | Empty state — alignment | `text-align:center` (1d "Empty") | `VStack(alignment: .leading, spacing: 4)` + `.frame(… alignment: .leading)` | `ShelfView.swift:255,263` | HIGH |
| 8 | Empty state — icon | 30×24 rect icon at opacity .3 above the headline | No icon | `ShelfView.swift:254-262` | HIGH |
| 9 | Undo button & footer icon buttons — rest-state color | `.undo{color:var(--tx2)}`, `.gbtn{color:var(--tx2)}` → `Theme.Colour.textSecondary` (62%/58%, built specifically because `.secondary` undershoots — see `Theme.swift:55-60`) | `.foregroundStyle(.secondary)` used instead (system ≈50%) | `ShelfRow.swift:150`; `ShelfView.swift:370,380` | HIGH |
| 10 | Project mode header — layout | `"PROJECT MODE"` label and `"End"` sit on **one row**, `justify-content:space-between`, above the destination chip (1d "Project mode") | Section label rendered alone at top; `"End"` button rendered at the **bottom**, stacked after the chip and caption | `ShelfView.swift:555-559,653-662` | HIGH |
| 11 | Project mode header — vertical padding | `padding:10px 12px 12px` → top 10, bottom 12 | top = `Theme.Space.panel` (12), bottom = 10 — **swapped** | `ShelfView.swift:665-666` | MEDIUM |
| 12 | Project mode header — divider | `border-bottom:1px solid rgba(10,108,214,.15)` under the tinted block | No border/divider drawn | `ShelfView.swift:663-668` | MEDIUM |
| 13 | Project-mode destination chip background | Forced opaque `background:#fff` over the tint | Still uses translucent `Theme.Colour.chipFill` | `ShelfView.swift:615-618` | MEDIUM |
| 14 | Badge label font-size | 7px for PDF/PNG/KEY, but **6.4px** for MOV/HEIC (design hand-tunes per glyph width) | Fixed `size: 7` for every extension | `TypeBadge.swift:62` | MEDIUM |
| 15 | Banner action text weight/decoration | `<b style="font-weight:600">` — no underline | `.actionLink()` = weight `.medium` (500) + `.underline()` | `ErrorBanner.swift:37-41`; `ShelfView.swift:487-490` | MEDIUM |
| 16 | Warning/unavailable-folder banner margin | `.banner{margin:8px 8px 0}` | `.padding(.horizontal, Theme.Space.panel)` = 12, not 8 | `ShelfView.swift:500-501`; `ErrorBanner.swift` call at `ShelfView.swift:543` (`horizontalPadding: 12`) | MEDIUM |
| 17 | Permission screen container/internal spacing | `padding:26px 24px 28px`; icon→title 9px, title→subtitle 3px, subtitle→button 12px | `padding(Theme.Space.panel)` = 12 all sides; single `spacing: 12` for every gap | `PermissionView.swift:20,67` | MEDIUM |
| 18 | Empty state padding | `padding:26px 20px 30px` (asymmetric) | `.padding(.horizontal, 12).padding(.vertical, 22)` | `ShelfView.swift:263-265` | MEDIUM |
| 19 | Empty-state headline weight | Plain 13px, **no** font-weight in source | `.titleText()` = 13pt **semibold** | `ShelfView.swift:256`; style at `Theme.swift:220-223` | MEDIUM |
| 20 | Dark image/movie badge fill alpha | image `.18`, movie `.16` | both coded at `.14` | `Theme.swift:87,90` | MEDIUM |
| 21 | Row name line-height | `.rname{line-height:16px}` for 13px text | `rowName()` sets only `font(size:13)`, no explicit line spacing (unlike `rowMeta()`, which the code comments say needs it) | `Theme.swift:180-182` | LOW |
| 22 | Empty-state title→subtitle gap | `margin-top:2px` | `VStack(spacing: 4)` | `ShelfView.swift:255` | LOW |
| 23 | Undo glyph size | SVG drawn ~14px, stroke 1.5 | SF Symbol at `size 11, weight .semibold` | `ShelfRow.swift:139` | LOW |

## In the design's shelf, not implemented
- Destination chip's two-part breadcrumb text (dimmed parent + `▸` + bright child, e.g. "Downloads ▸ Sorted") for the default (non-project) mode — we render a single plain name.
- Folded-corner flap on the type badge (see #3).
- Empty-state and permission-denied icons (see #4, #8).
- Project-mode header's top-row label/End layout and bottom divider (see #10, #12).

## We implement, design does not show
- Multi-folder listing in `PermissionView` (`blockedFolders.count > 1` branch, `PermissionView.swift:50-60`) — a reasonable addition, but styled with `.caption`/`.secondary` rather than any Theme type/color, inconsistent with the rest of the file.

**Counts: 9 HIGH, 11 MEDIUM, 3 LOW.**
