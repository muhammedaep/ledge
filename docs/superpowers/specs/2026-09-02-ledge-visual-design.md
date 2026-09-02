# The interface — design

**Goal:** Ledge looks like the design, in both themes, at Turkish length.

Nothing about Ledge's interface has ever been seen rendered by anyone who
designs. It was assembled from code by agents with no screen. This spec
replaces that with a drawn design and the scale behind it.

**Source of truth:** the Claude Design project *Ledge*,
`https://claude.ai/design/p/ced33f21-35be-496b-a214-a51b7c53e831`, file
`Ledge UI.dc.html`. Eight boards: `1a` shelf light English, `1b` shelf dark
Turkish, `1c` row hierarchy A/B/C, `1d` shelf states, `1e` Rules light,
`1f` Rules dark Turkish, `1g` Organize Now, `1h` the scale.

Where this spec and the boards disagree, §8 says so and why. Everywhere else
the boards win — the instruction was that it look exactly like the design.

## 1. The premise the design serves

A filed download stays reachable: the shelf lists recent files and each row
is a drag source. The design's central move is that **a row is a contained
chip, not a log line** — containment is the drag affordance. A stale row
loses its chip and goes flat, because flat reads as inert.

Board `1c` weighed two alternatives and rejected both, with reasons this
spec adopts: a right-aligned time column (three trailing claims on one edge,
which Turkish loses), and an explicit drag grip (on macOS a grip means
reorder, not drag out, and it costs ~16pt of the tightest budget in the app,
on every row). **Variant B — the merged metadata line — is the design.**

## 2. Type

Six styles, and nothing else in the app.

| Style | Used for |
|---|---|
| 13 semibold, primary | window titles, empty-state headline |
| 13 regular, primary | filenames, controls, buttons |
| 12 regular, primary | field text, sheet list rows |
| 11 regular, secondary | metadata line, captions, diagnostics |
| 11 semibold, +0.06em tracking, uppercase, tertiary | section labels |
| 10 semibold, +0.05em tracking, uppercase, tertiary | field labels in Rules |
| 11 SF Mono, primary | extensions, name patterns, globs |

`SF Pro Text` and `SF Mono` — the system faces, reached as
`.system(size:weight:)` and `.system(size:design:.monospaced)`.

## 3. Spacing, on a 4pt grid

Panel and window inset **12**. Card inset **8–10**. Icon to text **9**.
Name to metadata **1** — they are one object and must not read as two.
Row gap **3**. Section gap **14**.

Control heights: fields **22**, buttons **26**, the destination popup **28**.
A shelf row is **46** including its gap.

Corner radii: fields **5**, rows and banners **7**, cards **8**, windows
**10**, the shelf panel **11**.

## 4. Colour

**The principle, quoted from board `1h` because it is the whole system:**
*"Colour is opacity, not hue: primary label → 62% → 38% is the entire
hierarchy in both themes. Hue is reserved for meaning — accent blue =
actionable, amber = warning, red = will-never-work."*

Those three opacities are macOS's own label colours. `.primary`,
`.secondary` and `.tertiary` produce them in both themes and adapt on their
own; the design's rgba values and SwiftUI's hierarchical styles agree to the
decimal, so the tokens below are documentation, not literals to type in.

| Token | Light | Dark | In SwiftUI |
|---|---|---|---|
| label | `#1d1d1f` | `rgba(255,255,255,.92)` | `.primary` |
| label 2 | `rgba(60,60,67,.62)` | `rgba(235,235,245,.58)` | `.secondary` |
| label 3 | `rgba(60,60,67,.38)` | `rgba(235,235,245,.32)` | `.tertiary` |
| separator | `rgba(0,0,0,.09)` | `rgba(255,255,255,.1)` | `.separator` |

These four are literals, because no system colour matches them:

| Token | Light | Dark |
|---|---|---|
| chip fill | `rgba(255,255,255,.72)` | `rgba(255,255,255,.075)` |
| chip border | `rgba(0,0,0,.07)` | `rgba(255,255,255,.07)` |
| field fill | `#ffffff` | `rgba(255,255,255,.06)` |
| field border | `rgba(0,0,0,.14)` | `rgba(255,255,255,.14)` |

Meaning colours:

| Token | Light | Dark |
|---|---|---|
| accent | `#0a6cd6` | `#409cff` |
| amber | `#8a5d00` on `rgba(255,196,0,.14)` | `#ffd60a` on `rgba(255,214,10,.1)` |
| red | `#c4322a` on `rgba(255,59,48,.09)` | `#ff6961` on `rgba(255,105,97,.12)` |

Hover on a glyph button is `rgba(127,127,127,.16)`; on the undo button,
`rgba(127,127,127,.18)`. One neutral, both themes.

## 5. The shelf

360pt wide, radius 11, over a translucent blurred ground — see §8.2.

**Header.** The section label `FILING INTO`, then a 28pt chip naming the
destination: the folder, a `▸`, and a disclosure square 16×16 in accent
blue with a white chevron. The chip is the destination menu.

**Rows.** A 32pt type badge (§6), then a two-line text block — filename at
13 regular, truncating with an ellipsis; below it at 11 secondary, one
merged line reading `destination · subdivision · time`
(`Documents · PDF · 2 min ago`). Then, and only then, the undo button:
24×24, circular, secondary at rest, primary on hover.

**Undo is a real focusable button with a focus ring, never hover-only.**
The design states this and it settles the accessibility constraint: what
brightens on hover is emphasis, not existence.

**A stale row** drops its chip fill, border and shadow; its badge goes 35%
opacity and greyscale; its name falls to secondary and its metadata to
tertiary; its undo sits at 30%. It reads `Moved or deleted · 26 min ago` —
the status takes the destination's place in the same line.

**Footer**, 38pt, separated by a hairline: `Organize Now…` in accent at 13
regular on the left; two 28×26 glyph buttons on the right.

### States

- **Empty** — `Nothing filed yet` at 13 semibold, and beneath it
  `New downloads appear here — drag any row to use the file.` at 11
  secondary. That second line is the only place the product explains itself.
- **Warning** — an amber banner above the list, 11/14, with an action:
  `"Masaüstü" klasörü bulunamıyor. Dosyalama duraklatıldı.` /
  `Klasörü Yeniden Seç…`. The list stays; a blocked folder gets a banner,
  never a takeover.
- **Permission denied** — the list is replaced by
  `Ledge can't see your Downloads folder`, an explanation, and
  `Open System Settings…`. **The footer never disappears.**
- **Project mode** — the header is tinted, the menu bar icon fills, the
  header reads `Project mode` with the project name and
  `All new downloads go here until you end the project.`, and carries an
  `End` button. Rows filed under a project show the project name where the
  destination would be.

## 6. Type badges

The design replaces the macOS file icon with a drawn 32pt page carrying the
extension in caps.

Colour follows **the file's kind, read from its extension** — not the
category it was filed into. Board `1a` settles this: a screenshot filed into
`Screenshots` still carries the blue image badge. A PNG looks like an image
wherever it lands, which is also the only reading a user could predict.

Kind comes from `UTType(filenameExtension:)` and its conformance to
`.image`, `.movie` and `.content` — macOS's own answer, so a format nobody
has thought of yet is classified correctly without a list to maintain. The
lookup is pure and belongs in `LedgeCore` with tests.

| Kind | Page | Border | Text (light) | Text (dark) |
|---|---|---|---|---|
| Documents | `#fdeceb` | `#eec0bc` | `#c4544c` | `#ef9a92` |
| Images | `#eaf3fd` | `#bcd6f2` | `#3b74b5` | `#82b4ec` |
| Videos | `#f0ebfb` | `#d0c2ee` | `#7a5bc0` | `#c3a3ef` |

Every other kind takes a neutral treatment: the page in chip fill, the border
in chip border, the label at secondary. A file with no extension shows the
page with no label. **The boards do not draw this case** — they show only the
three families above — so the neutral treatment is this spec's invention and
should be looked at before it ships.

This is a real loss and it is accepted knowingly: a Sketch document stops
looking like a Sketch document. What is bought is a row that reads as one
designed object in both themes.

## 7. Settings and Organize Now

### Rules tab (560 × 460)

A one-line rubric under the tabs: `Rules apply top to bottom — the first
rule that claims a file wins.` Precedence is then carried twice more —
by a large ordinal in a 20pt gutter, and by reordering the card by dragging
that gutter.

**A rule card collapses to a single line when it is clean** and expands when
it has patterns or a diagnostic. Expanded it shows: the name; the extensions
field, 22pt, mono; the name-patterns field under the label
`NAME PATTERNS · ONE PER LINE`; and the subdivision segmented control
(`None` / `By ext.` / `By month`).

Diagnostics sit inside the card, amber for a warning and red for a rule that
can never match. The Turkish two-sentence diagnostic wraps to two lines and
the card grows; the list scrolls inside the fixed window, so a warning is
never clipped.

Below the list: `＋ Add Rule`, and a line naming where unclaimed files go.

### Organize Now (460 wide, list 260 tall)

A folder picker, then `N items would move. Folders move whole — Ledge never
files their contents.` Preview rows use the shelf's grammar: name on the
left, destination on the right (`Images ▸ HEIC`, `Documents · whole folder`).
Then `One undo restores the whole batch`, `Cancel`, and `Move N Items`.

## 8. Where the implementation departs from the boards

Five, each deliberate.

**8.1 Unclaimed files still go to `Other/`.** The boards say
`Everything else stays in Downloads` and show an unclaimed file as
`no rule — stays put`, counted out of the button (`23 items would move`,
`Move 22 Items`). That is a filing-behaviour change, not a visual one, and
the decision was to keep today's behaviour. So: the Rules footer names the
fallback category, the preview shows the fallback as a destination like any
other, and the button counts every planned move.

**8.2 Translucency is a material, not a colour.** The boards specify
`rgba(246,245,243,.82)` with `blur(36px)`, which is how the web imitates
macOS vibrancy. The panel takes a system material instead, so it behaves
correctly over any wallpaper and in both themes. The chip fills in §4 are
tuned against that ground and stay as given.

**8.3 Uppercase lives in the string catalog, never in `.textCase`.**
Section and field labels are drawn uppercase. SwiftUI uppercases with the
non-localised `String.uppercased()`, which turns Turkish `İ` into a dotless
`I`. Measured in this project twice. Every uppercase label ships uppercase
in the catalog.

**8.4 The accent is pinned.** `#0a6cd6` / `#409cff` rather than
`Color.accentColor`. A user who has set a pink system accent gets the
design's blue. That follows from "exactly like the design" and is recorded
here so it reads as a decision rather than an oversight.

**8.5 The rubric's wording changes.** The boards say `Rules apply top to
bottom — the first rule that claims a file wins.` The app currently ships
`Categories are matched top to bottom. The first one that claims a file
wins.` The board's wording replaces it, in both languages.

## 9. Strings

New keys, each needing a `tr` value and no `en` entry:
the empty-state second line; the warning banner's action; the permission
screen's headline, explanation and button; the project-mode caption and
`End`; the Rules rubric; `NAME PATTERNS · ONE PER LINE`; `＋ Add Rule`;
the Organize sheet's preview caption and its whole-folder marker.

Changed: the Rules rubric (§8.5) replaces the key shipped on 2026-09-01.

Uppercase keys ship uppercase, per §8.3. Turkish runs 27–38% longer than
English and the boards were drawn at that length; any string added later is
owed the same check.

## 10. Testing

Almost none of this can be tested automatically, and pretending otherwise
would be worse than saying so.

What can: the category-to-badge-family mapping is a pure function and belongs
in `LedgeCore` with tests. So does any string-length or truncation rule that
turns out to need logic rather than layout.

What cannot: every pixel. `docs/manual-checks.md` and its Turkish twin gain
a pass over both themes and both languages, and **the existing checks must
still pass** — the drag-out, undo, the stale row, project routing, the
folder-as-one-unit rule, the eject lockout. An interface that looks better
and breaks one of those is a loss.

## 11. Not in scope

The General tab. Drag-in-flight and drop states — the boards suggest them as
the next thing to draw, and they are not drawn yet. Any change to what Ledge
files, where it files it, or how rules are matched.
