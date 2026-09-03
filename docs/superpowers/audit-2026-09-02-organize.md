# Organize Now sheet — audit vs design source

Design source: `Ledge UI.dc.html` (project `ced33f21-35be-496b-a214-a51b7c53e831`), option **1g** "Organize Now · sheet · 460pt" (only Light/English mockup that exists for this sheet — see Limitations). Read in full (lines 1–243); tokens cross-checked against `1h` "Type & spacing scale" and the `.lt`/`.dk` CSS custom-property blocks (lines ~27–29).

Audited: `/Users/muhammed.celebi/Documents/ledge/Ledge/Organize/OrganizeSheet.swift`, `/Users/muhammed.celebi/Documents/ledge/Ledge/Design/Theme.swift`.

No prompt-injection attempts were found in the design file content — it is plain HTML/CSS mockup markup and prose design notes throughout.

## Discrepancy table

| # | Element | Design value (selector) | Our value | File:line | Severity |
|---|---|---|---|---|---|
| 1 | Folder label | Visible `"Folder"` text, 12px `var(--tx2)`, next to the popup chip (`1g` inline `font-size:12px;color:var(--tx2)`) | `.labelsHidden()` on the `Picker` — label never rendered | OrganizeSheet.swift:112-128 | HIGH |
| 2 | Folder control visual | Styled pill chip: folder icon, name, accent up/down-chevron badge (`.pop`/`.updn`, height 28 = `Size.popup`) | Plain unstyled `Picker`, no icon, no chip, no chevron badge | OrganizeSheet.swift:112-129 | HIGH |
| 3 | Row icons | Every row with a destination has a trailing arrow glyph (svg, `1g` row markup) between name and destination; whole-folder rows also get a leading folder glyph | No icons at all — just `Text` + `Spacer(minLength: 12)` + `Text` | OrganizeSheet.swift:162-171 | HIGH |
| 4 | Preview list container | Boxed: `border-radius:7px;border:1px solid var(--chipbd);background:var(--fieldbg)` around the 260px scroll area (`1g`) | Bare `List` with `.frame(height: 260)`, no border/background/radius applied — relies on system List chrome | OrganizeSheet.swift:155-187 | HIGH |
| 5 | Dividers around content | `1g`'s Organize sheet has **no** rule between header→box or box→footer (contrast: Settings Rules-tab footer and the shelf `.pfoot` both specify `border-top:1px solid var(--sep)`) | Explicit `Divider()` before `content` and again before `footer` | OrganizeSheet.swift:62, 65 | HIGH |
| 6 | "One undo restores the whole batch" color | `var(--tx3)` = `Theme.Colour.textTertiary` (38%/32%) (`1g` footer inline style) | `.rowMeta()` called with no override ⇒ defaults to `Theme.Colour.textSecondary` (62%/58%) | OrganizeSheet.swift:215-216 | HIGH |
| 7 | Category grouping UI | `1g` is one flat list of rows — no per-category headers or checkboxes anywhere | `Section` per category with a `Toggle` header (name, count, exclude-from-batch) — no counterpart in the design | OrganizeSheet.swift:156-184 | HIGH (structural addition, see note) |
| 8 | Row destination grammar | `"Images ▸ HEIC"`, `"Documents ▸ PDF"` — category **and** subdivision on every row (`1g` row spans) | `destinationLabel(for:)` returns only `item.destination.folder.lastPathComponent` (e.g. `"HEIC"`) — the category is never in the string, moved instead into the Section header | OrganizeSheet.swift:198-202 | MEDIUM |
| 9 | Header padding | `padding:16px 18px 0` (top 16 / sides 18 / bottom 0) (`1g` header block) | Hardcoded uniform `.padding(14)` — not sourced from `Theme.Space`, matches neither edge | OrganizeSheet.swift:132 | MEDIUM |
| 10 | Footer padding | `padding:12px 18px 14px` (`1g` footer block) | Uniform `.padding(12)` | OrganizeSheet.swift:235 | MEDIUM |
| 11 | Cancel/Move button chrome | `height:26px`, `border-radius:6px`, `font-size:12px`; Cancel = `var(--fieldbg)`/`var(--fieldbd)` border, Move = `var(--accent)` fill + `box-shadow:0 .5px 2px rgba(0,0,0,.25)` (`1g` footer buttons) | Plain `Button`, no `.buttonStyle`, no explicit font, no tint/fill/shadow — appearance is whatever the system default gives a `.defaultAction`/`.cancelAction` sheet button | OrganizeSheet.swift:229-233 | MEDIUM |
| 12 | Button corner radius token | `border-radius:6px` recurs on every filled/bordered pill in the file (`1g` buttons, `1d`'s "Open System Settings…") | `Theme.Radius` has no 6pt member (only `field=5, row=7, card=8, window=10, panel=11`) | Theme.Swift:42-48 | MEDIUM |
| 13 | List row insets | Row padding `7px 10px`, 8px internal gaps (`1g` row markup) | No `.listRowInsets`/custom padding set — native `List` row insets used, uncontrolled | OrganizeSheet.swift:161-172 | LOW |

## Known, accepted departure (not a defect)
Per project direction: the boards' `1g` shows an unclaimed file (`notes-inbox.txt`) staying in Downloads, dimmed, captioned `"no rule — stays put"`, and excluded from the button count (caption says 23, button says "Move 22 Items"). This app files unclaimed items to `Other/` instead, so `destinationLabel`/`movableCount` (OrganizeSheet.swift:198-202, 277) correctly give them a real destination and count them in both the caption and the button. This is the documented spec §8.1 departure, working as intended.

## Design → app: not implemented
- Folder popup chip visual (icon, accent chevron badge) — items 1–2 above.
- Row-level arrow/folder icons — item 3.
- Bordered/filled preview-list container — item 4.

## App → design: not in the mockup
- Per-category `Toggle` headers to exclude a category from the batch (item 7) — a real feature not depicted in the single static `1g` frame; may be intentional scope beyond the board, but there is no design source for its appearance (chip style, spacing, disabled-while-moving look) — flag for design follow-up.
- Post-batch `outcomeSummary` text ("Moved X of Y.") and the `"Undo Last Batch"` button (OrganizeSheet.swift:211-218, 242-250) — reasonable, since `1g` only depicts the pre-move state.
- `errorBanner` (OrganizeSheet.swift:257-264) — no error state shown for this sheet in the source (only the shelf panel's warning banner, `1d`, exists as a banner precedent).

## Token-reference (`1h`) coverage
Every value `1h` enumerates for type and spacing is honoured in `Theme.swift`: sizes 13/12/11 semibold+regular ↔ `titleText/rowName/fieldText/rowMeta/sectionLabel/mono`; spacing 12/8–10/9/1/3/14 ↔ `Space.panel/card/iconGap/nameToMeta/rowGap/section`; heights 22/26/28/46 ↔ `Size.field/button/popup/row`; radii 5/7/10–11 ↔ `Radius.field/row/window/panel`. The one gap found is the 6pt button/pill radius used throughout the mockups (item 12), which `1h`'s own summary never lists either — it's an undocumented-but-real design value with no `Theme.Radius` counterpart.

## Limitations
- `1g` is the only Organize Now sheet mockup in the source — Light/English only, no Dark or Turkish variant exists to check pixel-for-pixel. Turkish wording was instead checked against `Ledge/Resources/Localizable.xcstrings` directly: `"Organize Now"→"Şimdi Düzenle"`, caption, `"Move %lld Items"→"%lld Öğeyi Taşı"`, `"whole folder"→"klasörün tamamı"`, `"Cancel"→"İptal"`, `"Folder"→"Klasör"`, undo/outcome strings — all translated and consistent with the Turkish vocabulary the design uses elsewhere (e.g. shelf's "Şimdi Düzenle…"). No wording discrepancy found there.
- English caption/button text (`"%lld items would move…"`, `"Move %lld Items"`, `"One undo restores the whole batch"`) matches the design's literal English strings verbatim.
