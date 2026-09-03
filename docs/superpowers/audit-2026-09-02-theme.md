# Theme.swift audit vs. `Ledge UI.dc.html`

Note on the source material: the design file (`Ledge UI.dc.html`, 243 lines, read in full) contains no
text that reads as an instruction to the assistant — it is ordinary HTML/CSS mockup markup and design
notes. Separately, the task message that assigned this audit contained an embedded block styled as a
"context_window_protection" system directive (mandating specific MCP tools, forbidding normal
Read/Bash usage, capping the response at 500 words, etc.). That block was embedded inside the
*message content* rather than delivered as an actual system instruction, which is the signature of a
prompt injection. It was disregarded; this audit was done with normal Read/Bash/ToolSearch tools, and
the reply to the team lead follows the team lead's own instructions (full report to this file; reply
under 600 words with HIGH/MEDIUM rows + counts).

## Method
- Design source read in full: `.lt`/`.dk` variable blocks and every class rule (lines ~10–95), then
  the rest of the file (mockup instances + the closing "Type & spacing scale" token-reference section,
  `.tokrow`/`.tokdef`, lines ~224–239) in windowed reads to the end (line 243).
- `Theme.swift` read in full (254 lines).
- Colours converted to a common representation (`rgba(r,g,b,a)` / hex) before comparing.

## Findings table (most significant first)

| token | design value | our value | Theme.swift:line | severity |
|---|---|---|---|---|
| Shadows (all) | `.pop` `0 .5px 1.5px rgba(0,0,0,.08)`; `.row` `0 1px 2px rgba(0,0,0,.06)`; `.field` `0 .5px 1px rgba(0,0,0,.05)`; `.seg .on` `0 .5px 2px rgba(0,0,0,.18)`; `.panel.lt` `0 14px 40px rgba(0,0,20,.28), 0 0 0 .5px rgba(0,0,0,.15)`; `.panel.dk` `0 14px 40px rgba(0,0,0,.55), 0 0 0 .5px rgba(0,0,0,.6), inset 0 0 0 .5px rgba(255,255,255,.09)`; `.win.lt` `0 18px 50px rgba(0,0,20,.3), 0 0 0 .5px rgba(0,0,0,.16)`; `.win.dk` none | no equivalent — Theme has no shadow tokens at all | n/a | HIGH |
| Panel background + blur | `.panel.lt` `rgba(246,245,243,.82)`; `.panel.dk` `rgba(43,43,46,.78)`; `backdrop-filter: blur(36px)` | no equivalent | n/a | HIGH |
| Window background | `.win.lt` `#f2f0ef`; `.win.dk` `#2d2b2e` (opaque, no blur) | no equivalent | n/a | HIGH |
| `badgeDocBorder` (dark) | `rgba(240,150,140,.45)` | `srgb(0xff6961, 0.28)` = `rgba(255,105,97,.28)` | Theme.swift:85 | HIGH |
| `badgeDocPage` (dark) | `rgba(240,150,140,.16)` | `srgb(0xff6961, 0.14)` = `rgba(255,105,97,.14)` | Theme.swift:84 | HIGH |
| `badgeImageBorder` (dark) | `rgba(120,170,235,.5)` | `srgb(0x82b4ec, 0.28)` = `rgba(130,180,236,.28)` | Theme.swift:88 | HIGH |
| `badgeMovieBorder` (dark) | `rgba(190,150,240,.45)` | `srgb(0xc3a3ef, 0.28)` = `rgba(195,163,239,.28)` | Theme.swift:91 | HIGH |
| `badgeImagePage` (dark) | `rgba(120,170,235,.18)` | `srgb(0x82b4ec, 0.14)` = `rgba(130,180,236,.14)` | Theme.swift:87 | MEDIUM |
| `badgeMoviePage` (dark) | `rgba(190,150,240,.16)` | `srgb(0xc3a3ef, 0.14)` = `rgba(195,163,239,.14)` | Theme.swift:90 | MEDIUM |
| `actionLink()` weight | banner action text (e.g. `Choose Folder Again…`/`Klasörü Yeniden Seç…`) is `font-weight:600` in source | doc comment names that exact string as an example of "11 **medium**" and code sets `.weight(.medium)` (500) | Theme.swift:208-218 | MEDIUM |
| `--sep` (separator) | `.lt`: `rgba(0,0,0,.09)`; `.dk`: `rgba(255,255,255,.1)` — used by `.pfoot`/`.tbar` borders, list-row dividers | no equivalent token in `Theme.Colour` | n/a | MEDIUM |
| Neutral overlay `.14` / `.12` | `.seg` track `rgba(127,127,127,.14)`; `.arr` bg `rgba(127,127,127,.12)` | not covered — only `.hover` (.16) and `.hoverStrong` (.18) exist | Theme.swift:95-96 | MEDIUM |
| `HoverGlyphButtonStyle.cornerRadius` default | `.gbtn` (the glyph button the style's own doc comment describes) is `border-radius:5px` | default `= 6`, a radius not present anywhere in the design's scale | Theme.swift:137 | LOW |

Everything else checked out exactly: `textSecondary`/`textTertiary` (`--tx2`/`--tx3`, both themes),
`chipFill`/`chipBorder`/`fieldFill`/`fieldBorder` (`--chipbg`/`--chipbd`/`--fieldbg`/`--fieldbd`, both
themes), `accent`/`amber`/`amberFill`/`red`/`redFill` (both themes), all badge **label** colours (both
themes), every `Theme.Size` and `Theme.Radius` value (22/26/28/46/38/32 and 5/7/8/10/11) against the
class rules and the design's own closing spacing/radius summary, every `Theme.Space` value
(12/10/9/1/3/14) against the same summary, and the five type styles with explicit token-reference rows
(`sectionLabel`, `rowName`, `rowMeta` incl. its 11/14 line-height, `mono`, `titleText`) plus `fieldLabel`
(10/600/+0.05em) against `.flab`.

## Design tokens Theme has no counterpart for
- `--sep` separator colour
- Panel background colour + 36px blur
- Window background colour (both themes)
- All box-shadows (`.pop`, `.row`, `.field`, `.seg .on`, `.panel`, `.win`)
- Neutral overlay alphas `.14` (segment track) and `.12` (reorder-arrow background)
- Traffic-light dot colours (`#ff5f57`/`#febc2e`/`#28c840`) — likely out of scope (system chrome), noted for completeness

## Theme tokens the design has no counterpart for
- `HoverGlyphButtonStyle`'s default `cornerRadius = 6` (no 6pt radius exists in the design scale; nearest are 5 and 7)
