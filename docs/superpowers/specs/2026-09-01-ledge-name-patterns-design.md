# Filing by filename — design

**Goal:** screenshots get their own folder.

They arrive as `.png`, so the `Images` rule claims them and they land beside
every other image. A rule needs to be able to say something about a file's
*name*, not only its extension.

Scope is deliberately one signal. Where a download came from
(`kMDItemWhereFroms`), its content type (UTI), its size and its age were all
considered and all left out — the goal named screenshots, and three more signal
types would triple the model to serve a case nobody asked for.

## 1. What a category matches

`Category` gains one field:

```swift
public var namePatterns: [String]
```

A category claims a file when **every condition it states** is satisfied. A
condition it leaves empty is not a constraint.

| Category | `extensions` | `namePatterns` | Claims |
|---|---|---|---|
| Screenshots | — | `CleanShot *` | any file named that way (the shipped rule is §5) |
| Images | `png`, `jpg` | — | any png or jpg — **unchanged** |
| Delivery | `aep` | `*_final*` | only when both hold |

Within one list the members are alternatives: any listed extension, any listed
pattern.

This is the whole rule. There is no all/any switch, and every category that
exists today — none of which has a pattern — keeps its exact behaviour.

**A category stating no conditions at all claims nothing.** Not everything.
The natural reading of "every condition is satisfied" over an empty set is
*true*, which would make an empty rule swallow the entire folder, and an empty
rule is what a half-finished one in the editor looks like. This is the one
place the general rule is deliberately broken, and it needs its own test.

## 2. Pattern syntax

Glob, with exactly two metacharacters:

- `*` — any run of characters, including none
- `?` — exactly one character

Matched against the **whole filename including its extension**
(`url.lastPathComponent`), so `CleanShot *` matches
`CleanShot 2026-09-01 at 11.14.08@2x.png`.

No character classes, no ranges, no escaping. A filename containing a literal
`*` or `?` cannot be matched exactly; that is a documented limit, not an
oversight — escaping doubles the matcher's surface to serve filenames nobody
has.

### Case

Matching folds case with Swift's `lowercased()` on both the pattern and the
name.

Explicitly **not** `lowercased(with: Locale.current)`. Under a Turkish locale
that maps `I` to `ı`, so a pattern written on a Turkish Mac would stop matching
the same file on an English one — the same class of trap already measured in
this project, where SwiftUI's `.textCase(.uppercase)` turned
`Son İndirilenler` into `SON İNDIRILENLER`. `lowercased()` is
locale-independent: both sides fold identically, and accented letters still
match their capitals.

### Implementation

A pure-Swift matcher in `LedgeCore`, not `fnmatch(3)`. `fnmatch`'s
case-insensitive flag `FNM_CASEFOLD` is a BSD extension, it folds bytes rather
than characters, and its behaviour is not something this project's tests could
pin down. Two metacharacters is a small enough language to write and to test
exhaustively.

## 3. Which category wins

Unchanged: the first category in the list that claims the file. Order is
user-editable and the editor already says so — *"Move up — earlier rules win
ties"*.

No implicit specificity. A pattern rule does not beat an extension rule by
being "more specific": that would put two different precedence rules in play at
once, and the sentence already in the editor would become false.

This makes **placement load-bearing**. A `Screenshots` rule below `Images` never
fires, because `Images` claims `png` first. §5 says exactly where it goes.

## 4. Subdivision with no extension

A pattern-only category can now claim a file with no extension at all. With
`subdivision: .byExtension` that would build a folder whose name is the empty
string.

When the extension is empty, subdivision is skipped and the file goes directly
into the category folder. `.byMonth` is unaffected.

## 5. The Screenshots category

Added to `RuleSet.defaults`:

```swift
Category(name: "Screenshots",
         extensions: [],
         namePatterns: ["CleanShot *", "Screenshot *", "Screen Shot *"],
         subdivision: .none)
```

Three patterns, each verified rather than guessed: `CleanShot ` is what
CleanShot X writes (measured — `CleanShot 2026-09-01 at 11.14.08@2x.png`),
`Screenshot ` is macOS's current English name and `Screen Shot ` its older one.

**Localised macOS screenshot names are not covered.** A Turkish-language macOS
names them differently, and this spec will not guess at a string it has not
seen. The editor makes the patterns visible and editable, which is the right
place for a user to add their own.

Screen *recordings* from the same tools carry the same prefix and will be filed
here too. That is intended: they are screen captures.

### Placement

Inserted immediately **above the first category claiming `png`** — the rule
that would otherwise take screenshots. If no category claims `png`, it goes
first.

Stated as a position relative to a competitor rather than a fixed index, so it
stays correct against a rule set the user has already reordered.

## 6. Getting it into rules that already exist

A saved `rules.json` has no `Screenshots`. Adding it to `defaults` alone would
reach only new installs.

`RuleSet` gains:

```swift
public var appliedMigrations: [String]   // kept sorted
```

`RuleSet.migrated()` — a pure function — inserts the category per §5 and
records `"screenshots-category"`. It is a no-op when the marker is already
present, and it records the marker without inserting anything when a category
named `Screenshots` already exists.

The marker is what stops a rule the user *deleted* from reappearing on the next
launch. Without it the migration is not a migration, it is a policy.

`RuleSet.defaults` ships with the marker already set, so a new install is never
migrated.

`AppState` runs it after `RulesStore.load()` and saves only when the result
differs. `load()` itself stays free of side effects.

### Decoding an older file

`Category` gets a hand-written `init(from:)` using `decodeIfPresent` for
`namePatterns`, defaulting to `[]`; `RuleSet` does the same for
`appliedMigrations`. Swift's synthesised `Codable` would reject every existing
file for a missing key.

## 7. Editor

`RulesPane` gains a patterns field per category, beside the extensions field.

Without it the Screenshots rule would be a box the user can neither see, edit
nor remove — and Ledge would have written a rule into their file that they have
no way to reach. That is the same shape as the surprise this rule was written
after, where the right behaviour arrived unannounced.

### One pattern per line

The extensions field separates tokens on commas **or whitespace**. A pattern
cannot use that separator: `CleanShot *` contains a space, and splitting on
whitespace would store it as two patterns, `CleanShot` and `*` — the second of
which claims every file in the folder. Commas are no safer; a filename may
contain one.

A newline is the only separator a filename cannot contain. The patterns field
is therefore multi-line, one pattern per line, and its round-trip mirrors the
extensions field's:

```swift
var namePatternsField: String            // patterns joined by newlines
static func parseNamePatterns(_ text: String) -> [String]
```

`parseNamePatterns` splits on newlines, trims each line, drops empty and
whitespace-only lines, and collapses duplicates keeping first position — so
feeding `namePatternsField` back through it returns the same list, which is
what lets the editor re-tidy a field in place without changing its meaning.

Patterns are stored **as typed**, not lowercased. `Category.init` lowercases
extensions because `Categorizer` compares against a lowercase
`pathExtension`; patterns fold case at match time instead (§2), and storing
them folded would show the user something they did not write.

## 8. A category with no extensions is no longer a defect

`RuleEditing`'s diagnostics flag `noExtensions` for any category with an empty
extension list. The Screenshots rule has exactly that — it is pattern-only — so
Ledge would ship a rule and immediately warn the user about it.

The condition becomes **no conditions at all**: flagged only when `extensions`
and `namePatterns` are both empty. That is the same rule as §1, where such a
category claims nothing, and it is the case actually worth a warning.

The diagnostic's identifier and its sentence both change, so the sentence stays
true of what triggers it.

## 9. Testing

`LedgeCore` carries the whole decision, so all of it is testable without an app.

- **Glob matcher** — literals, `*` at each position, `*` matching nothing,
  multiple `*`, `?` against one character and against none, case folding both
  directions, an empty pattern, a pattern that is only `*`, and a name
  containing a literal `*`.
- **`Category.matches`** — each of the four combinations of empty/non-empty
  condition lists, including the empty-rule-claims-nothing case from §1.
- **`Categorizer`** — a screenshot reaching Screenshots ahead of Images; the
  same file reaching Images when the Screenshots rule sits below it; a
  pattern-only category with `.byExtension` and an extension-less file (§4);
  every existing categorization test passing unchanged.
- **`RuleSet.migrated()`** — inserted above the `png` claimant; first when
  nothing claims `png`; no-op when the marker is set; marker recorded without
  insertion when `Screenshots` already exists; a user's reordered rule set.
- **Decoding** — a `rules.json` written before this change loads with empty
  patterns and no migration marker.
- **`parseNamePatterns`** — a pattern containing spaces survives as one
  pattern; a pattern containing a comma survives as one pattern; blank lines
  are dropped; the round-trip through `namePatternsField` is stable.
- **Diagnostics** — a pattern-only category raises no warning; a category with
  neither extensions nor patterns does.

Each test must be shown to fail against the defect it was written for, as the
rest of this project's suite is.

## 10. Not in scope

Source-of-download, content type, size and age rules. Diagnostics for a pattern
shadowed by an earlier rule — §5's placement is what makes the shipped rule
work, and a general shadowing warning is a separate piece of work.
