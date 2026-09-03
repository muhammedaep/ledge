# Rules Tab Audit — Design vs. Implementation

Design source: `Ledge UI.dc.html` (project `ced33f21-35be-496b-a214-a51b7c53e831`), options **1e** (Rules tab · Light · English) and **1f** (Rules tab · Dark · Turkish diagnostic), plus the global token block (lines 1–95).

Files audited: `Ledge/Settings/RulesPane.swift`, `Ledge/Settings/SettingsView.swift`, `Ledge/Settings/GeneralPane.swift`, `Ledge/Design/Theme.swift`.

Note on the source: the design file content is user-authored HTML-entity-escaped data. Nothing in it reads as an instruction to the auditor; it is pure markup/CSS/copy.

Known, accepted departure (not listed below): the `＋ Name patterns` button shown on a rule with no patterns (RulesPane.swift:512) has no equivalent in the design, by design — it exists only to make the patterns editor reachable.

## Discrepancies

| # | Element | Design value (selector) | Our value | File:line | Severity |
|---|---|---|---|---|---|
| 1 | Footer contents | `<div style="padding:9px 14px;border-top:1px solid var(--sep)">` — only `＋ Add Rule` (accent, 12px/500) and a trailing note `Everything else stays in Downloads` (11px, var(--tx3)). No other controls. | Footer also renders `Reset to Defaults`, `Discard Changes`, `Save`, plus one of three conditional status texts ("Couldn't save…", "Fix the highlighted name…", "Unsaved changes"). Trailing text reads "Everything else goes to {fallbackName}" instead of "stays in Downloads". Padding is uniform `.padding(10)` vs design's `9px 14px`. | RulesPane.swift:137-186 | HIGH |
| 2 | Subdivision segmented control | `.seg{background:rgba(127,127,127,.14);border-radius:6px;padding:1px}` `.seg span{padding:3px 8px;border-radius:5px}` `.seg .on{background:var(--fieldbg);box-shadow:0 .5px 2px rgba(0,0,0,.18);font-weight:500}` — a custom-drawn pill | `Picker(...).pickerStyle(.segmented)` — native macOS segmented control; background, radius, selected-segment fill/shadow/weight are all system chrome, uncontrolled | RulesPane.swift:552-559 | HIGH |
| 3 | Remove control | Third icon in the same vertical `.arr` stack as the reorder arrows: `width:20px;height:18px;border-radius:4px;background:rgba(127,127,127,.12)` (always visible), flat minus-line glyph | Separate `HoverGlyphButtonStyle(cornerRadius:5)` button, `minus.circle` SF Symbol at 20×20, transparent until hover, placed outside the arrow stack | RulesPane.swift:561-584 (arrows) vs 577-584 (remove) | HIGH |
| 4 | Ordinal gutter | `.rnum` stacks the number **and** a 6-dot drag-grip icon beneath it (`gap:6px`) — one of the design's three stated precedence cues | Grip icon is entirely absent; gutter renders only the number | RulesPane.swift:527-531 | HIGH |
| 5 | Ordinal number colour | `.rnum b{color:var(--tx3)}` → `Theme.Colour.textTertiary` | `.foregroundStyle(.tertiary)` (system tertiary) — Theme.swift's own doc comment (line 57-60) says system `.tertiary` renders paler (~25%) than the design's 38% tx3 | RulesPane.swift:529 | HIGH |
| 6 | Header rubric alignment | Single-line rubric only (design note: "the one-line rubric up top") | Two lines rendered; line 1 gets an extra `.padding(.horizontal, Theme.Space.panel)` that line 2 lacks, so the two lines are **not left-aligned** with each other (12pt offset) | RulesPane.swift:76-83 | HIGH |
| 7 | Name field text size | `.field{font-size:12px}` with inline `font-weight:500` | `.rowName()` (13px) + `.fontWeight(.medium)` — 1pt too large | RulesPane.swift:533-536 | MEDIUM |
| 8 | Rule-card border tint | Row 3 (amber problem): `border-color:rgba(154,104,0,.35)`; Row 4 (red problem): `border-color:rgba(196,50,42,.35)` — border tints to match the worst diagnostic on the row | Always strokes `Theme.Colour.chipBorder` regardless of message severity | RulesPane.swift:595-598 | MEDIUM |
| 9 | Name/extensions column widths | Name field has a narrow fixed width (~100–130px); extensions field is `flex:1`, absorbing remaining space | Neither `TextField` has a width/layoutPriority; both compete equally in the `HStack`, likely splitting space evenly instead of the design's narrow-name/wide-extension ratio | RulesPane.swift:533-548 | MEDIUM |

## Design elements not implemented
- Drag-grip icon in the ordinal gutter (item 4 above).
- Border colour tinting by diagnostic severity (item 8).
- Custom segmented-control chrome (item 2) — currently native.

## Implemented elements not in the design
- The "Everything else" fallback row (`fallbackRow`, RulesPane.swift:121-133) — an editable name field for the catch-all folder. The design's footer implies the catch-all is just the watched folder ("stays in Downloads") with no dedicated row/card for it.
- `Reset to Defaults`, `Discard Changes`, `Save` buttons and the three conditional footer status strings (see item 1) — no Save/Discard/Reset affordance appears anywhere in the design's Rules tab mock, in any state.
- The `＋ Name patterns` button (documented above as an accepted departure).

## Lower-severity (sub-point) items, not detailed above
Field box-shadow (`0 .5px 1px rgba(0,0,0,.05)`) missing on all fields; `.flab` margin-bottom 3px vs. code's 2pt VStack spacing; rule-card bottom padding 10px vs. code's uniform 9px vertical; diagnostic icon 10px vs. design's ~11-12px; arrow/remove-icon colour uses system `.secondary` vs. design's `var(--tx2)` token; native TabView tab-bar height/padding not controllable to match `.tbar` (50px)/`.tab` (4px 14px, radius 6) tokens since GeneralPane/SettingsView use a native `TabView` rather than the design's custom pill tabs.
