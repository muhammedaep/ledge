# Filing by filename — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A filing rule can match a file's name, so screenshots get their own folder instead of landing in `Images` with every other `.png`.

**Architecture:** `Category` gains `namePatterns`, matched by a small glob matcher in `LedgeCore`. A category claims a file when every condition it states is satisfied; a condition it leaves empty is not a constraint, so every existing rule behaves exactly as before. A `Screenshots` category joins the defaults and reaches saved rule sets through a one-time, marker-recorded migration.

**Tech Stack:** Swift 6, Swift Testing (`@Test`, `#expect`), SwiftUI. `LedgeCore` is a dependency-free SPM package; `Ledge` is the app target.

**Spec:** `docs/superpowers/specs/2026-09-01-ledge-name-patterns-design.md`

## Global Constraints

- Swift 6 language mode in both targets. No new dependencies.
- `LedgeCore` produces data; the app target produces sentences. No `String(localized:)`, `NSLocalizedString`, `LocalizedError`, `LocalizedStringResource` or `LocalizedStringKey` anywhere under `LedgeCore/Sources/` — `make strings` check 2 fails the build otherwise.
- Every user-visible string is a key in `Ledge/Resources/Localizable.xcstrings` with a `tr` value (check 1), and its `en` value must equal the key exactly (check 3). Prefer omitting the `en` entry entirely.
- Never use `.textCase(.uppercase)` or `lowercased(with: Locale.current)` on user-facing or matched text. Measured in this project: Turkish `I`/`İ` folding breaks both.
- Every test must be demonstrated to fail against the defect it was written for. Break the line under test, run the test, watch it fail, restore, run again. Record both runs in the task report.
- Never write to, delete from, or "clean up" the user's real data, including `~/Library/Application Support/Ledge/`. Report unexpected state; do not tidy it.
- Tests that touch the filesystem work in their own temporary directory (`TempDirectory.swift`). No test may touch `~/Library`.
- Run `cd LedgeCore && swift test`, then `make build`, then `make strings` before every commit that touches their inputs.

---

### Task 1: The glob matcher

**Files:**
- Create: `LedgeCore/Sources/LedgeCore/Rules/Glob.swift`
- Test: `LedgeCore/Tests/LedgeCoreTests/GlobTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `Glob.matches(pattern: String, name: String) -> Bool`

Spec §2. Two metacharacters, `*` and `?`. Case folded with `lowercased()` on both sides — locale-independent, so a pattern written on a Turkish Mac matches the same file on an English one.

- [ ] **Step 1: Write the failing tests**

Create `LedgeCore/Tests/LedgeCoreTests/GlobTests.swift`:

```swift
import Testing
@testable import LedgeCore

@Test func literalPatternMatchesOnlyItself() {
    #expect(Glob.matches(pattern: "notes.txt", name: "notes.txt"))
    #expect(!Glob.matches(pattern: "notes.txt", name: "notes.txt.bak"))
    #expect(!Glob.matches(pattern: "notes.txt", name: "my notes.txt"))
}

@Test func starMatchesARunOfCharacters() {
    #expect(Glob.matches(pattern: "CleanShot *", name: "CleanShot 2026-09-01 at 11.14.08@2x.png"))
    #expect(!Glob.matches(pattern: "CleanShot *", name: "Cleanshot.png"))
}

@Test func starMatchesNothingAtAll() {
    #expect(Glob.matches(pattern: "report*.pdf", name: "report.pdf"))
}

@Test func starMatchesAtEveryPosition() {
    #expect(Glob.matches(pattern: "*.png", name: "a.png"))
    #expect(Glob.matches(pattern: "IMG*", name: "IMG_0001.heic"))
    #expect(Glob.matches(pattern: "*final*", name: "hero_final_v2.aep"))
}

@Test func multipleStarsBacktrackCorrectly() {
    #expect(Glob.matches(pattern: "*a*b*c", name: "xxaxxbxxc"))
    #expect(!Glob.matches(pattern: "*a*b*c", name: "xxaxxbxxd"))
}

@Test func questionMarkMatchesExactlyOneCharacter() {
    #expect(Glob.matches(pattern: "IMG_????.png", name: "IMG_0042.png"))
    #expect(!Glob.matches(pattern: "IMG_????.png", name: "IMG_042.png"))
    #expect(!Glob.matches(pattern: "IMG_????.png", name: "IMG_00042.png"))
}

@Test func matchingFoldsCaseBothWays() {
    #expect(Glob.matches(pattern: "cleanshot *", name: "CleanShot 1.png"))
    #expect(Glob.matches(pattern: "CleanShot *", name: "cleanshot 1.png"))
    #expect(Glob.matches(pattern: "RÉSUMÉ*", name: "résumé.pdf"))
}

@Test func emptyPatternMatchesOnlyAnEmptyName() {
    #expect(Glob.matches(pattern: "", name: ""))
    #expect(!Glob.matches(pattern: "", name: "a"))
}

@Test func aLoneStarMatchesEverythingIncludingNothing() {
    #expect(Glob.matches(pattern: "*", name: ""))
    #expect(Glob.matches(pattern: "*", name: "anything at all.png"))
}

@Test func aLiteralStarInANameIsNotMatchableExactly() {
    // Documented limit (spec §2): there is no escaping, so `*` in a pattern is
    // always the metacharacter. This test pins the limit down rather than
    // leaving it as folklore.
    #expect(Glob.matches(pattern: "star*.png", name: "star*.png"))
    #expect(Glob.matches(pattern: "star*.png", name: "starlight.png"))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LedgeCore && swift test --filter GlobTests`
Expected: FAIL to compile — "cannot find 'Glob' in scope".

- [ ] **Step 3: Write the matcher**

Create `LedgeCore/Sources/LedgeCore/Rules/Glob.swift`:

```swift
import Foundation

/// Matches a filename against a shell-style pattern.
///
/// Two metacharacters and no escaping: `*` for any run of characters including
/// none, `?` for exactly one. That is the whole language. Character classes and
/// escaping would double this file's surface to serve filenames nobody has, and
/// a pattern a user cannot predict is worse than one they cannot write.
///
/// Not `fnmatch(3)`: its case-insensitive flag `FNM_CASEFOLD` is a BSD
/// extension, it folds bytes rather than characters, and its behaviour is not
/// something these tests could pin down.
public enum Glob {
    /// Whether `name` matches `pattern`, folding case.
    ///
    /// `lowercased()` and deliberately not `lowercased(with: Locale.current)`.
    /// Under a Turkish locale the latter maps `I` to `ı`, so a pattern written
    /// on a Turkish Mac would stop matching the same file on an English one.
    /// `lowercased()` is locale-independent: both sides fold identically, and
    /// accented letters still match their capitals.
    ///
    /// Compares `Character`s rather than unicode scalars, so `?` matches one
    /// grapheme — one thing the user would call a character — rather than
    /// splitting an emoji or a combining sequence in half.
    public static func matches(pattern: String, name: String) -> Bool {
        let p = Array(pattern.lowercased())
        let s = Array(name.lowercased())

        var pi = 0
        var si = 0
        // Where the most recent `*` sat, and how much of the name it had
        // consumed. Backtracking to here is what lets a later literal fail
        // without failing the whole match.
        var lastStar = -1
        var lastStarConsumed = 0

        while si < s.count {
            if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1
                si += 1
            } else if pi < p.count, p[pi] == "*" {
                lastStar = pi
                lastStarConsumed = si
                pi += 1
            } else if lastStar >= 0 {
                lastStarConsumed += 1
                si = lastStarConsumed
                pi = lastStar + 1
            } else {
                return false
            }
        }

        // Trailing `*`s have nothing left to consume and match the empty rest.
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LedgeCore && swift test --filter GlobTests`
Expected: PASS, 10 tests.

- [ ] **Step 5: Prove each test can fail**

For each mutation below, apply it, run `swift test --filter GlobTests`, record which tests fail, then restore.

| Mutation | Must fail |
|---|---|
| `p[pi] == "?" \|\| p[pi] == s[si]` → `p[pi] == "?"` | `literalPatternMatchesOnlyItself` |
| delete the `while pi < p.count, p[pi] == "*" { pi += 1 }` line | `starMatchesNothingAtAll`, `aLoneStarMatchesEverythingIncludingNothing` |
| `lastStarConsumed += 1` → `lastStarConsumed += 0` | `multipleStarsBacktrackCorrectly` (hangs or fails — if it hangs, that is still the test doing its job; kill it and record that) |
| `Array(pattern.lowercased())` → `Array(pattern)` | `matchingFoldsCaseBothWays` |
| `p[pi] == "?"` → `false` | `questionMarkMatchesExactlyOneCharacter` |

A mutation that fails nothing means the test for it does not exist yet. Write it before continuing.

- [ ] **Step 6: Commit**

```bash
git add LedgeCore/Sources/LedgeCore/Rules/Glob.swift LedgeCore/Tests/LedgeCoreTests/GlobTests.swift
git commit -m "feat(core): glob matcher for filing by filename"
```

---

### Task 2: A category can state a name pattern

**Files:**
- Modify: `LedgeCore/Sources/LedgeCore/Rules/Category.swift`
- Test: `LedgeCore/Tests/LedgeCoreTests/CategoryMatchingTests.swift` (create)

**Interfaces:**
- Consumes: `Glob.matches(pattern:name:)` from Task 1.
- Produces:
  - `Category.namePatterns: [String]`
  - `Category.init(id:name:extensions:namePatterns:subdivision:)` — `namePatterns` defaults to `[]`, placed after `extensions`
  - `Category.matches(name: String, extension ext: String) -> Bool`

Spec §1. Every condition the category states must hold; an empty list is not a constraint; a category stating nothing claims nothing.

- [ ] **Step 1: Write the failing tests**

Create `LedgeCore/Tests/LedgeCoreTests/CategoryMatchingTests.swift`:

```swift
import Testing
@testable import LedgeCore

@Test func extensionOnlyCategoryIgnoresTheName() {
    let images = Category(name: "Images", extensions: ["png"])
    #expect(images.matches(name: "anything.png", extension: "png"))
    #expect(!images.matches(name: "anything.jpg", extension: "jpg"))
}

@Test func patternOnlyCategoryIgnoresTheExtension() {
    let shots = Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    #expect(shots.matches(name: "CleanShot 1.png", extension: "png"))
    #expect(shots.matches(name: "CleanShot 1.mov", extension: "mov"))
    #expect(!shots.matches(name: "holiday.png", extension: "png"))
}

@Test func bothStatedMeansBothMustHold() {
    let delivery = Category(name: "Delivery", extensions: ["aep"], namePatterns: ["*_final*"])
    #expect(delivery.matches(name: "hero_final.aep", extension: "aep"))
    #expect(!delivery.matches(name: "hero_final.psd", extension: "psd"))
    #expect(!delivery.matches(name: "hero_draft.aep", extension: "aep"))
}

@Test func anyOneOfSeveralPatternsIsEnough() {
    let shots = Category(name: "Screenshots", extensions: [],
                         namePatterns: ["CleanShot *", "Screenshot *"])
    #expect(shots.matches(name: "Screenshot 2026-09-01.png", extension: "png"))
    #expect(shots.matches(name: "CleanShot 2026-09-01.png", extension: "png"))
}

@Test func aCategoryStatingNoConditionsClaimsNothing() {
    // Spec §1: the natural reading of "every stated condition holds" over an
    // empty set is *true*, which would make a half-typed rule in the editor
    // swallow the whole folder. This is the one place that reading is refused.
    let empty = Category(name: "Empty", extensions: [])
    #expect(!empty.matches(name: "anything.png", extension: "png"))
    #expect(!empty.matches(name: "", extension: ""))
}

@Test func aCategoryWithNoExtensionsStillRejectsAnExtensionlessNameItDoesNotMatch() {
    let shots = Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    #expect(!shots.matches(name: "README", extension: ""))
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LedgeCore && swift test --filter CategoryMatchingTests`
Expected: FAIL to compile — no `namePatterns:` argument, no `matches` method.

- [ ] **Step 3: Add the field, the initializer argument, the matcher and the decoder**

In `LedgeCore/Sources/LedgeCore/Rules/Category.swift`, replace the whole `Category` struct with:

```swift
/// One filing rule: a destination folder name and the conditions a file must
/// satisfy to be filed there.
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var extensions: [String]

    /// Glob patterns matched against the whole filename, extension included.
    ///
    /// Stored as typed, not lowercased. `extensions` is lowercased on the way
    /// in because `Categorizer` compares it against a lowercase
    /// `pathExtension`; patterns fold case at match time instead, and storing
    /// them folded would show the user something they did not write.
    public var namePatterns: [String]

    public var subdivision: Subdivision

    public init(
        id: UUID = UUID(),
        name: String,
        extensions: [String],
        namePatterns: [String] = [],
        subdivision: Subdivision = .none
    ) {
        self.id = id
        self.name = name
        self.extensions = extensions.map { $0.lowercased() }
        self.namePatterns = namePatterns
        self.subdivision = subdivision
    }

    /// Whether this category claims a file.
    ///
    /// Every condition the category *states* must hold; a condition it leaves
    /// empty is not a constraint. That single rule covers all three useful
    /// shapes — extensions only, patterns only, both — without an all/any
    /// switch, and leaves every rule written before patterns existed behaving
    /// exactly as it did.
    ///
    /// The exception is a category that states nothing at all, which claims
    /// nothing rather than everything. Over an empty set the rule above reads
    /// *true*, and a rule half-typed in the editor is exactly that shape: it
    /// would swallow the whole folder between two keystrokes.
    ///
    /// `ext` is expected already lowercased, as `Categorizer` supplies it.
    public func matches(name: String, extension ext: String) -> Bool {
        if extensions.isEmpty && namePatterns.isEmpty { return false }
        if !extensions.isEmpty && !extensions.contains(ext) { return false }
        if !namePatterns.isEmpty
            && !namePatterns.contains(where: { Glob.matches(pattern: $0, name: name) }) {
            return false
        }
        return true
    }

    /// Hand-written so a `rules.json` saved before patterns existed still
    /// loads. Swift's synthesised decoder rejects a file missing any key, and
    /// every rule set already on disk is missing this one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        extensions = try container.decode([String].self, forKey: .extensions).map { $0.lowercased() }
        namePatterns = try container.decodeIfPresent([String].self, forKey: .namePatterns) ?? []
        subdivision = try container.decode(Subdivision.self, forKey: .subdivision)
    }
}
```

Leave `enum Subdivision` above it untouched.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LedgeCore && swift test`
Expected: PASS. Every existing test still passes — `namePatterns` defaults to `[]`, so no existing call site changes.

- [ ] **Step 5: Prove each test can fail**

| Mutation | Must fail |
|---|---|
| `if extensions.isEmpty && namePatterns.isEmpty { return false }` → `{ return true }` | `aCategoryStatingNoConditionsClaimsNothing` |
| delete that line entirely | `aCategoryStatingNoConditionsClaimsNothing` |
| `if !extensions.isEmpty && !extensions.contains(ext)` → `if !extensions.contains(ext)` | `patternOnlyCategoryIgnoresTheExtension` |
| `if !namePatterns.isEmpty && !namePatterns.contains(...)` → `if !namePatterns.contains(...)` | `extensionOnlyCategoryIgnoresTheName` |
| `namePatterns.contains(where:)` → `namePatterns.allSatisfy` | `anyOneOfSeveralPatternsIsEnough` |

- [ ] **Step 6: Commit**

```bash
git add LedgeCore/Sources/LedgeCore/Rules/Category.swift LedgeCore/Tests/LedgeCoreTests/CategoryMatchingTests.swift
git commit -m "feat(core): a category can state a name pattern"
```

---

### Task 3: Categorizer asks the category

**Files:**
- Modify: `LedgeCore/Sources/LedgeCore/Rules/Categorizer.swift`
- Test: `LedgeCore/Tests/LedgeCoreTests/CategorizerTests.swift` (append)

**Interfaces:**
- Consumes: `Category.matches(name:extension:)` from Task 2.
- Produces: no new API. `Categorizer.destination(for:in:using:)` keeps its signature.

Spec §3 and §4.

- [ ] **Step 1: Write the failing tests**

Append to `LedgeCore/Tests/LedgeCoreTests/CategorizerTests.swift`:

```swift
@Test func aPatternRuleAboveAnExtensionRuleWins() {
    let rules = RuleSet(categories: [
        Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"]),
        Category(name: "Images", extensions: ["png"])
    ])
    let shot = facts("CleanShot 2026-09-01 at 11.14.08@2x.png")
    #expect(Categorizer.destination(for: shot, in: root, using: rules).category == "Screenshots")
}

@Test func theSameRuleBelowLosesToTheExtensionRule() {
    // Order is the only precedence (spec §3). This is what makes placement
    // load-bearing, and it is why the migration in RuleSet inserts above the
    // png claimant rather than appending.
    let rules = RuleSet(categories: [
        Category(name: "Images", extensions: ["png"]),
        Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    ])
    let shot = facts("CleanShot 2026-09-01 at 11.14.08@2x.png")
    #expect(Categorizer.destination(for: shot, in: root, using: rules).category == "Images")
}

@Test func aPatternRuleClaimsAFileWithNoExtension() {
    let rules = RuleSet(categories: [
        Category(name: "Notes", extensions: [], namePatterns: ["README*"])
    ])
    #expect(Categorizer.destination(for: facts("README"), in: root, using: rules).category == "Notes")
}

@Test func subdivisionByExtensionIsSkippedWhenThereIsNoExtension() {
    // Otherwise the destination is a folder whose name is the empty string.
    let rules = RuleSet(categories: [
        Category(name: "Notes", extensions: [], namePatterns: ["README*"],
                 subdivision: .byExtension)
    ])
    let result = Categorizer.destination(for: facts("README"), in: root, using: rules)
    #expect(result.folder == root.appendingPathComponent("Notes"))
}

@Test func subdivisionByExtensionStillAppliesWhenThereIsOne() {
    let rules = RuleSet(categories: [
        Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"],
                 subdivision: .byExtension)
    ])
    let result = Categorizer.destination(for: facts("CleanShot 1.png"), in: root, using: rules)
    #expect(result.folder == root.appendingPathComponent("Screenshots").appendingPathComponent("PNG"))
}

@Test func aPlainFolderNamedLikeAPatternIsStillNotFiled() {
    // The directory guard predates patterns and must survive them: a folder
    // called "CleanShot archive" is a folder, not a screenshot.
    let rules = RuleSet(categories: [
        Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    ])
    let folder = facts("CleanShot archive", isDirectory: true)
    #expect(Categorizer.destination(for: folder, in: root, using: rules).category == rules.fallbackName)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LedgeCore && swift test --filter CategorizerTests`
Expected: FAIL — `aPatternRuleAboveAnExtensionRuleWins` reports `Other`, because matching still reads `extensions` directly.

- [ ] **Step 3: Rewrite the matching and the subdivision**

In `Categorizer.destination(for:in:using:)`, replace the body from `let ext = ...` down to the `switch category.subdivision { ... }` with:

```swift
        let name = facts.url.lastPathComponent
        let ext = facts.url.pathExtension.lowercased()

        // A folder named "footage.mp4" is not a video. A directory matches only
        // when a rule claims it *and* the system reports it as a package — see
        // `FileFacts.isPackage`. Asking macOS, rather than checking a list this
        // app maintains, is what lets a user add `sketch` to a category and
        // have real Sketch documents routed there instead of silently landing
        // in the fallback.
        //
        // The old `!ext.isEmpty` guard is gone: a pattern-only rule can claim a
        // file with no extension, and an extension rule still cannot, because
        // an empty `ext` matches no entry in any extension list.
        guard !(facts.isDirectory && !facts.isPackage),
              let category = rules.categories.first(where: {
                  $0.matches(name: name, extension: ext)
              })
        else {
            return Destination(
                folder: root.appendingPathComponent(rules.fallbackName),
                category: rules.fallbackName
            )
        }

        var folder = root.appendingPathComponent(category.name)
        switch category.subdivision {
        case .none:
            break
        case .byExtension:
            // A pattern-only rule can now reach here with nothing to subdivide
            // by. Appending an empty component would build a folder whose name
            // is the empty string.
            if !ext.isEmpty { folder.appendPathComponent(ext.uppercased()) }
        case .byMonth:
            folder.appendPathComponent(Self.monthFormatter.string(from: facts.creationDate))
        }
```

Leave `monthFormatter` and the `return Destination(...)` at the end unchanged.

- [ ] **Step 4: Run the whole suite**

Run: `cd LedgeCore && swift test`
Expected: PASS, including every categorization test that existed before.

- [ ] **Step 5: Prove each test can fail**

| Mutation | Must fail |
|---|---|
| `first(where: { $0.matches(...) })` → `first(where: { $0.extensions.contains(ext) })` | `aPatternRuleAboveAnExtensionRuleWins`, `aPatternRuleClaimsAFileWithNoExtension` |
| `rules.categories.first` → `rules.categories.last` | `theSameRuleBelowLosesToTheExtensionRule` |
| `if !ext.isEmpty { folder.appendPathComponent(...) }` → `folder.appendPathComponent(ext.uppercased())` | `subdivisionByExtensionIsSkippedWhenThereIsNoExtension` |
| delete `!(facts.isDirectory && !facts.isPackage)` from the guard | `aPlainFolderNamedLikeAPatternIsStillNotFiled` |

- [ ] **Step 6: Commit**

```bash
git add LedgeCore/Sources/LedgeCore/Rules/Categorizer.swift LedgeCore/Tests/LedgeCoreTests/CategorizerTests.swift
git commit -m "feat(core): categorize by name pattern as well as extension"
```

---

### Task 4: The Screenshots category, and getting it into rules that already exist

**Files:**
- Modify: `LedgeCore/Sources/LedgeCore/Rules/RuleSet.swift`
- Test: `LedgeCore/Tests/LedgeCoreTests/RuleSetMigrationTests.swift` (create)
- Test: `LedgeCore/Tests/LedgeCoreTests/RuleSetTests.swift` (append)

**Interfaces:**
- Consumes: `Category.init(id:name:extensions:namePatterns:subdivision:)` from Task 2.
- Produces:
  - `RuleSet.appliedMigrations: [String]`
  - `RuleSet.init(categories:fallbackName:appliedMigrations:)` — `appliedMigrations` defaults to `[]`
  - `RuleSet.screenshotsMigration: String` (`"screenshots-category"`)
  - `RuleSet.screenshotsCategory: Category`
  - `RuleSet.migrated() -> RuleSet`

Spec §5 and §6.

- [ ] **Step 1: Write the failing tests**

Create `LedgeCore/Tests/LedgeCoreTests/RuleSetMigrationTests.swift`:

```swift
import Testing
import Foundation
@testable import LedgeCore

private func ruleSet(_ categories: [Category], applied: [String] = []) -> RuleSet {
    RuleSet(categories: categories, fallbackName: "Other", appliedMigrations: applied)
}

@Test func screenshotsIsInsertedAboveThePngClaimant() {
    let before = ruleSet([
        Category(name: "Documents", extensions: ["pdf"]),
        Category(name: "Images", extensions: ["png", "jpg"]),
        Category(name: "Code", extensions: ["json"])
    ])
    let after = before.migrated()
    #expect(after.categories.map(\.name) == ["Documents", "Screenshots", "Images", "Code"])
}

@Test func screenshotsGoesFirstWhenNothingClaimsPng() {
    let before = ruleSet([Category(name: "Documents", extensions: ["pdf"])])
    #expect(before.migrated().categories.map(\.name) == ["Screenshots", "Documents"])
}

@Test func migrationRecordsItsMarker() {
    let after = ruleSet([Category(name: "Images", extensions: ["png"])]).migrated()
    #expect(after.appliedMigrations.contains(RuleSet.screenshotsMigration))
}

@Test func migrationIsANoOpOnceTheMarkerIsRecorded() {
    // This is what stops a rule the user deleted from coming back on the next
    // launch. Without the marker the migration is not a migration, it is a
    // policy.
    let deleted = ruleSet([Category(name: "Images", extensions: ["png"])],
                          applied: [RuleSet.screenshotsMigration])
    let after = deleted.migrated()
    #expect(after.categories.map(\.name) == ["Images"])
    #expect(after == deleted)
}

@Test func anExistingScreenshotsCategoryIsNotDuplicated() {
    let existing = ruleSet([
        Category(name: "screenshots", extensions: ["png"]),
        Category(name: "Images", extensions: ["png"])
    ])
    let after = existing.migrated()
    #expect(after.categories.count == 2)
    #expect(after.appliedMigrations.contains(RuleSet.screenshotsMigration))
}

@Test func migrationRespectsAReorderedRuleSet() {
    let reordered = ruleSet([
        Category(name: "Images", extensions: ["png"]),
        Category(name: "Documents", extensions: ["pdf"])
    ])
    #expect(reordered.migrated().categories.map(\.name) == ["Screenshots", "Images", "Documents"])
}

@Test func theShippedScreenshotsRuleCatchesRealScreenshotNames() {
    let shots = RuleSet.screenshotsCategory
    for name in ["CleanShot 2026-09-01 at 11.14.08@2x.png",
                 "Screenshot 2026-09-01 at 11.14.08.png",
                 "Screen Shot 2020-01-01 at 09.00.00.png"] {
        #expect(shots.matches(name: name, extension: "png"), "did not claim \(name)")
    }
    #expect(!shots.matches(name: "holiday.png", extension: "png"))
}

@Test func defaultsAreAlreadyMigrated() {
    // A fresh install ships the category, so it must also ship the marker —
    // otherwise the first launch would try to insert a second one.
    #expect(RuleSet.defaults.appliedMigrations.contains(RuleSet.screenshotsMigration))
    #expect(RuleSet.defaults.migrated() == RuleSet.defaults)
}

@Test func defaultsPutScreenshotsAboveImages() {
    let names = RuleSet.defaults.categories.map(\.name)
    let shots = names.firstIndex(of: "Screenshots")
    let images = names.firstIndex(of: "Images")
    #expect(shots != nil)
    #expect(images != nil)
    #expect(shots! < images!)
}
```

Append to `LedgeCore/Tests/LedgeCoreTests/RuleSetTests.swift`:

```swift
@Test func aRuleSetSavedBeforePatternsExistedStillDecodes() {
    let json = Data("""
    {
      "categories": [
        { "id": "01434B4D-4C7B-4027-ACD4-4BCCF10AFAC1",
          "name": "Images",
          "extensions": ["png", "jpg"],
          "subdivision": "none" }
      ],
      "fallbackName": "Other"
    }
    """.utf8)
    let decoded = try! JSONDecoder().decode(RuleSet.self, from: json)
    #expect(decoded.categories.count == 1)
    #expect(decoded.categories[0].namePatterns.isEmpty)
    #expect(decoded.appliedMigrations.isEmpty)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LedgeCore && swift test --filter RuleSetMigrationTests`
Expected: FAIL to compile — no `appliedMigrations:` argument, no `screenshotsMigration`, no `migrated()`.

- [ ] **Step 3: Add the field, the category, the migration and the decoder**

In `LedgeCore/Sources/LedgeCore/Rules/RuleSet.swift`, replace the stored properties and `init` at the top of the struct with:

```swift
    public var categories: [Category]
    public var fallbackName: String

    /// Which one-time edits Ledge has already made to this rule set, by name.
    ///
    /// Kept sorted so the saved file is byte-stable across runs.
    ///
    /// This is what separates a migration from a policy. Adding `Screenshots`
    /// to `defaults` reaches only new installs; running the insert on every
    /// launch would put back a rule the user deliberately deleted. The marker
    /// says "this was offered once", which is the whole of the promise.
    public var appliedMigrations: [String]

    public init(
        categories: [Category],
        fallbackName: String = "Other",
        appliedMigrations: [String] = []
    ) {
        self.categories = categories
        self.fallbackName = fallbackName
        self.appliedMigrations = appliedMigrations.sorted()
    }

    /// Hand-written for the same reason as `Category`'s: every `rules.json`
    /// already on disk is missing this key, and the synthesised decoder would
    /// reject all of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([Category].self, forKey: .categories)
        fallbackName = try container.decode(String.self, forKey: .fallbackName)
        appliedMigrations =
            (try container.decodeIfPresent([String].self, forKey: .appliedMigrations) ?? []).sorted()
    }
```

Then add, after `destinationFolderNames`:

```swift
    public static let screenshotsMigration = "screenshots-category"

    /// The rule that gives screen captures their own folder.
    ///
    /// Patterns only, because a screenshot is a `.png` like any other and the
    /// extension is exactly what fails to distinguish it.
    ///
    /// Three prefixes, each seen rather than guessed: `CleanShot ` is what
    /// CleanShot X writes, `Screenshot ` is macOS's current English name and
    /// `Screen Shot ` its older one. Localised macOS names are not covered —
    /// this list will not guess at a string nobody has looked at — and the
    /// editor is where a user adds their own.
    ///
    /// Screen *recordings* from the same tools carry the same prefix and land
    /// here too. That is intended: they are screen captures.
    public static let screenshotsCategory = Category(
        name: "Screenshots",
        extensions: [],
        namePatterns: ["CleanShot *", "Screenshot *", "Screen Shot *"]
    )

    /// This rule set with every one-time edit applied that it has not seen.
    ///
    /// Pure, so the decision is testable and the writing is the caller's.
    ///
    /// `Screenshots` goes immediately above the first category claiming `png`,
    /// stated as a position relative to its competitor rather than a fixed
    /// index so it stays correct against a rule set the user has reordered.
    /// Below that category it would never fire, because first match wins.
    public func migrated() -> RuleSet {
        guard !appliedMigrations.contains(Self.screenshotsMigration) else { return self }

        var result = self
        result.appliedMigrations = (appliedMigrations + [Self.screenshotsMigration]).sorted()

        // A category the user already calls Screenshots is theirs. Compared by
        // `folderNameKey`, which is how the rest of the app decides two names
        // are the same folder on a case-insensitive disk.
        let wanted = Category.folderNameKey(Self.screenshotsCategory.name)
        guard !categories.contains(where: { Category.folderNameKey($0.name) == wanted })
        else { return result }

        let index = categories.firstIndex { $0.extensions.contains("png") } ?? 0
        result.categories.insert(Self.screenshotsCategory, at: index)
        return result
    }
```

Finally, in `defaults`, insert the screenshots rule before `Images` and record the marker. Replace the `public static let defaults = RuleSet(categories: [` line and the `Category(name: "Images", ...)` entry with:

```swift
    public static let defaults = RuleSet(categories: [
        screenshotsCategory,
        Category(name: "Images",
                 extensions: ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "avif", "tiff", "bmp", "dng"],
                 subdivision: .byExtension),
```

and change the closing of `defaults` from `])` to:

```swift
    ], appliedMigrations: [screenshotsMigration])
```

- [ ] **Step 4: Run the whole suite**

Run: `cd LedgeCore && swift test`
Expected: PASS, with no existing test edited. Checked while writing this plan: no test counts the default categories, and the two tests that loop over their extensions (`defaultExtensionsAreLowercasedAndDotless`, `noExtensionAppearsInTwoCategories`) are unaffected because `Screenshots` has none. `ruleSetSurvivesEncodeDecode` now also exercises the `appliedMigrations` round-trip. If any existing test does fail, stop and report it rather than editing it — it is telling you something this plan got wrong.

- [ ] **Step 5: Prove each test can fail**

| Mutation | Must fail |
|---|---|
| `guard !appliedMigrations.contains(...) else { return self }` → delete the line | `migrationIsANoOpOnceTheMarkerIsRecorded` |
| `result.appliedMigrations = ...` → delete the line | `migrationRecordsItsMarker`, `migrationIsANoOpOnceTheMarkerIsRecorded` |
| `firstIndex { $0.extensions.contains("png") } ?? 0` → `categories.count` | `screenshotsIsInsertedAboveThePngClaimant`, `defaultsPutScreenshotsAboveImages` (if defaults are rebuilt), `migrationRespectsAReorderedRuleSet` |
| delete the `guard !categories.contains(where:)` block | `anExistingScreenshotsCategoryIsNotDuplicated` |
| `namePatterns: ["CleanShot *", "Screenshot *", "Screen Shot *"]` → drop `"Screen Shot *"` | `theShippedScreenshotsRuleCatchesRealScreenshotNames` |
| `decodeIfPresent(...) ?? []` → `decode(...)` in `RuleSet.init(from:)` | `aRuleSetSavedBeforePatternsExistedStillDecodes` |

- [ ] **Step 6: Commit**

```bash
git add LedgeCore/Sources/LedgeCore/Rules/RuleSet.swift LedgeCore/Tests/LedgeCoreTests/RuleSetMigrationTests.swift LedgeCore/Tests/LedgeCoreTests/RuleSetTests.swift
git commit -m "feat(core): a Screenshots rule, and a marked one-time migration to carry it"
```

---

### Task 5: The editor's model — a patterns field, and a diagnostic that is true again

**Files:**
- Modify: `LedgeCore/Sources/LedgeCore/Rules/RuleEditing.swift`
- Modify: `Ledge/Settings/RulesPane.swift` — one `case`, because the rename breaks it
- Modify: `Ledge/Resources/Localizable.xcstrings` — one key swapped
- Test: `LedgeCore/Tests/LedgeCoreTests/RuleEditingTests.swift` (append)

**Interfaces:**
- Consumes: `Category.namePatterns` from Task 2.
- Produces:
  - `Category.namePatternsField: String`
  - `Category.parseNamePatterns(_ text: String) -> [String]`
  - `RuleSet.Problem.noConditions(category: Category.ID)` — replaces `.noExtensions(category:)`

Spec §7 and §8.

- [ ] **Step 1: Write the failing tests**

Append to `LedgeCore/Tests/LedgeCoreTests/RuleEditingTests.swift`:

```swift
@Test func patternsAreSeparatedByNewlinesNotSpaces() {
    // The extensions field splits on whitespace. A pattern contains spaces —
    // "CleanShot *" — and splitting it the same way would store two patterns,
    // the second of which is `*` and claims every file in the folder.
    let parsed = Category.parseNamePatterns("CleanShot *\nScreenshot *")
    #expect(parsed == ["CleanShot *", "Screenshot *"])
}

@Test func aPatternMayContainACommaOrASpace() {
    #expect(Category.parseNamePatterns("invoice, final*.pdf") == ["invoice, final*.pdf"])
}

@Test func blankAndWhitespaceOnlyLinesAreDropped() {
    #expect(Category.parseNamePatterns("\n  \nCleanShot *\n\n   ") == ["CleanShot *"])
}

@Test func duplicatePatternsCollapseKeepingFirstPosition() {
    #expect(Category.parseNamePatterns("b*\na*\nb*") == ["b*", "a*"])
}

@Test func patternsAreStoredAsTyped() {
    // Unlike extensions, which are lowercased on the way in.
    #expect(Category.parseNamePatterns("CleanShot *") == ["CleanShot *"])
}

@Test func thePatternsFieldRoundTrips() {
    let category = Category(name: "Screenshots", extensions: [],
                            namePatterns: ["CleanShot *", "Screenshot *"])
    #expect(Category.parseNamePatterns(category.namePatternsField) == category.namePatterns)
}

@Test func aPatternOnlyCategoryIsNotFlaggedAsEmpty() {
    let rules = RuleSet(categories: [
        Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    ])
    #expect(!rules.problems.contains { if case .noConditions = $0 { return true }; return false })
}

@Test func aCategoryWithNeitherExtensionsNorPatternsIsFlagged() {
    let rules = RuleSet(categories: [Category(name: "Empty", extensions: [])])
    #expect(rules.problems.contains { if case .noConditions = $0 { return true }; return false })
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LedgeCore && swift test --filter RuleEditingTests`
Expected: FAIL to compile — no `parseNamePatterns`, no `namePatternsField`, no `.noConditions`.

- [ ] **Step 3: Add the field round-trip**

In `LedgeCore/Sources/LedgeCore/Rules/RuleEditing.swift`, in the `public extension Category` block, after `extensionsField`, add:

```swift
    /// The stored patterns as the text the editor shows, one per line.
    ///
    /// The inverse of `parseNamePatterns`, so feeding this back through it
    /// returns the same list.
    var namePatternsField: String { namePatterns.joined(separator: "\n") }
```

and after `parseExtensions`, add:

```swift
    /// Turns a typed or pasted patterns field into the list to store.
    ///
    /// One pattern per line, and the separator is not negotiable: the
    /// extensions field splits on commas or whitespace, and a pattern contains
    /// spaces — `CleanShot *` split that way stores two patterns, the second
    /// being `*`, which claims every file in the folder. A filename may contain
    /// a comma too. A newline is the only separator a filename cannot contain.
    ///
    /// Patterns are stored as typed. `parseExtensions` lowercases because
    /// `Categorizer` compares against a lowercase `pathExtension`; `Glob` folds
    /// case at match time instead, so folding here would only show the user
    /// something they did not write.
    ///
    /// Duplicates within the field collapse, keeping first position, as the
    /// extensions field does.
    static func parseNamePatterns(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let pattern = line.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty, seen.insert(pattern).inserted else { continue }
            result.append(pattern)
        }
        return result
    }
```

- [ ] **Step 4: Make the empty-category diagnostic true again**

Three edits in the same file.

Rename the case, keeping it beside `shadowedExtension`:

```swift
        /// The category states no conditions at all — no extensions and no
        /// patterns — so nothing can ever match it. Renamed from
        /// `noExtensions`, which stopped being true the moment a category could
        /// be pattern-only: a Screenshots rule has no extensions by design, and
        /// warning about it would mean Ledge shipping a rule and immediately
        /// calling it a mistake.
        case noConditions(category: Category.ID)
```

In the `category` accessor, change `case let .noExtensions(id)` to `case let .noConditions(id)`.

In `problems`, change:

```swift
            if category.extensions.isEmpty {
                found.append(.noExtensions(category: category.id))
            }
```

to:

```swift
            if category.extensions.isEmpty && category.namePatterns.isEmpty {
                found.append(.noConditions(category: category.id))
            }
```

- [ ] **Step 5: Follow the rename into the app target**

Renaming the case breaks the one place that reads it, so it is fixed here
rather than in the next task — a commit that does not build is a commit nobody
can bisect through.

In `Ledge/Settings/RulesPane.swift`, change:

```swift
            case .noExtensions:
                messages.append(RuleMessage(
                    text: String(localized: "No extensions, so nothing is ever filed here."),
                    isBlocking: false))
```

to:

```swift
            case .noConditions:
                messages.append(RuleMessage(
                    text: String(localized: "No extensions and no patterns, so nothing is ever filed here."),
                    isBlocking: false))
```

In `Ledge/Resources/Localizable.xcstrings`, remove the key
`No extensions, so nothing is ever filed here.` and add
`No extensions and no patterns, so nothing is ever filed here.` with the `tr`
value `Uzantı da desen de yok, buraya hiçbir şey klasörlenmez.` and **no `en`
entry** — check 3 requires any `en` value to equal its key, and omitting it
makes the key itself the English text.

- [ ] **Step 6: Run the whole gate**

Run: `cd LedgeCore && swift test`, then `make build`, then `make strings`
Expected: tests PASS, build succeeds, all three string checks OK.

- [ ] **Step 7: Prove each test can fail**

| Mutation | Must fail |
|---|---|
| `text.split(whereSeparator: \.isNewline)` → `text.split(whereSeparator: { $0.isNewline \|\| $0.isWhitespace })` | `patternsAreSeparatedByNewlinesNotSpaces`, `aPatternMayContainACommaOrASpace` |
| delete `guard !pattern.isEmpty` | `blankAndWhitespaceOnlyLinesAreDropped` |
| delete `seen.insert(pattern).inserted` from the guard | `duplicatePatternsCollapseKeepingFirstPosition` |
| `line.trimmingCharacters(in: .whitespaces)` → `String(line)` | `blankAndWhitespaceOnlyLinesAreDropped` |
| `namePatterns.joined(separator: "\n")` → `joined(separator: " ")` | `thePatternsFieldRoundTrips` |
| `extensions.isEmpty && namePatterns.isEmpty` → `extensions.isEmpty` | `aPatternOnlyCategoryIsNotFlaggedAsEmpty` |
| `extensions.isEmpty && namePatterns.isEmpty` → `false` | `aCategoryWithNeitherExtensionsNorPatternsIsFlagged` |

- [ ] **Step 8: Commit**

```bash
git add LedgeCore/Sources/LedgeCore/Rules/RuleEditing.swift \
        LedgeCore/Tests/LedgeCoreTests/RuleEditingTests.swift \
        Ledge/Settings/RulesPane.swift \
        Ledge/Resources/Localizable.xcstrings
git commit -m "feat(core): a patterns field, and an empty-rule warning that is true again"
```

---

### Task 6: The patterns field in the rules editor

**Files:**
- Modify: `Ledge/Settings/RulesPane.swift`
- Modify: `Ledge/Resources/Localizable.xcstrings`

**Interfaces:**
- Consumes: `Category.namePatternsField`, `Category.parseNamePatterns(_:)`, `RuleSet.Problem.noConditions` from Task 5.
- Produces: no API.

Spec §7. There are no tests here — the app target has none by design, which is exactly why every rule above lives in `LedgeCore`. Keep this task to wiring.

- [ ] **Step 1: Add the field's state**

In the category row view, beside `_typedExtensions`, add a state property and initialize it. Find:

```swift
        _typedExtensions = State(initialValue: category.wrappedValue.extensionsField)
```

and add immediately after:

```swift
        _typedPatterns = State(initialValue: category.wrappedValue.namePatternsField)
```

Declare it beside the existing `@State private var typedExtensions` (find that declaration and add below it):

```swift
    @State private var typedPatterns: String
```

- [ ] **Step 2: Add the field to the row**

In `body`, immediately after the `MessageList(messages: rewriteNotes)` line that follows the Extensions field, insert:

```swift
                // A TextEditor rather than TextField(axis: .vertical): on macOS
                // Return in a vertical TextField submits rather than inserting a
                // newline, and a newline is this field's separator (see
                // `Category.parseNamePatterns`). A control the user cannot type
                // the separator into is not a control.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name patterns — one per line, * matches anything")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $typedPatterns)
                        .font(.caption.monospaced())
                        .scrollContentBackground(.hidden)
                        .frame(height: 46)
                        .padding(4)
                        .overlay {
                            RoundedRectangle(cornerRadius: 5)
                                .strokeBorder(.separator)
                        }
                }
```

- [ ] **Step 3: Keep the draft current**

Beside the existing `.onChange(of: typedExtensions)`, add:

```swift
        .onChange(of: typedPatterns) { _, text in
            let parsed = Category.parseNamePatterns(text)
            if parsed != category.namePatterns { category.namePatterns = parsed }
        }
        // Follows the list when something other than typing changes it —
        // Reset to Defaults and Discard Changes both do.
        .onChange(of: category.namePatterns) { _, list in
            if list != Category.parseNamePatterns(typedPatterns) {
                typedPatterns = list.joined(separator: "\n")
            }
        }
```

- [ ] **Step 4: Add the string**

Add this key to `Ledge/Resources/Localizable.xcstrings` with a `tr` value and
**no `en` entry** — check 3 requires any `en` value to equal its key, and
omitting it makes the key itself the English text.

| Key | `tr` |
|---|---|
| `Name patterns — one per line, * matches anything` | `Ad desenleri — satır başına bir tane, * her şeyi karşılar` |

- [ ] **Step 5: Build and check the strings**

Run: `make build && make strings`
Expected: build succeeds; all three checks report OK.

- [ ] **Step 6: Commit**

```bash
git add Ledge/Settings/RulesPane.swift Ledge/Resources/Localizable.xcstrings
git commit -m "feat: edit a category's name patterns"
```

---

### Task 7: Run the migration on launch

**Files:**
- Modify: `Ledge/AppState.swift`

**Interfaces:**
- Consumes: `RuleSet.migrated()` from Task 4, `RulesStore.load()`, `RulesStore.save(_:)`.
- Produces: no API.

Spec §6. `RulesStore.load()` stays free of side effects; the app decides to write.

- [ ] **Step 1: Find where rules are loaded**

In `Ledge/AppState.swift`, the initializer reads `rulesStore.load()` and then checks `rulesStore.lastLoadWasCorrupt` / `lastLoadWasRepaired`. The migration runs after that check, so a rule set that was just quarantined and replaced by defaults is not migrated twice.

- [ ] **Step 2: Apply and save**

Immediately after the `lastLoadWasCorrupt` / `lastLoadWasRepaired` branch and before `projects = projectStore.load()`, insert:

```swift
        // One-time edits Ledge makes to a rule set it did not write. Saved only
        // when something actually changed, so a rule set already carrying every
        // marker is never rewritten — and a save that fails leaves the marker
        // unrecorded, which means the migration is offered again rather than
        // silently lost.
        let migrated = rules.migrated()
        if migrated != rules {
            do {
                try rulesStore.save(migrated)
                rules = migrated
            } catch {
                notice = Notice(message: String(localized: "Couldn't save your rules."))
            }
        }
```

- [ ] **Step 3: Build**

Run: `make build && make strings`
Expected: build succeeds; all three checks OK. No new strings — `Couldn't save your rules.` is already in the catalog.

- [ ] **Step 4: Verify by hand against a copy, never the real file**

Do **not** edit `~/Library/Application Support/Ledge/rules.json`. Copy it to a scratch directory, run the migration against the copy in a throwaway Swift snippet, and confirm the result has `Screenshots` above `Images` and the marker recorded. Report what the copy showed.

If the real file is in an unexpected state, report it. Do not repair it.

- [ ] **Step 5: Commit**

```bash
git add Ledge/AppState.swift
git commit -m "feat: add the Screenshots rule to rule sets written before it existed"
```

---

## After the last task

Run the full gate once more: `cd LedgeCore && swift test`, `make build`, `make strings`.

Then add to `docs/manual-checks.md` and `docs/manual-checks.tr.md` — both, they are the same list — a check for this feature:

> **Screenshots get their own folder.** Take a screenshot into a watched folder.
> It should land in `Screenshots/`, not `Images/`. Open Settings → Rules: the
> Screenshots rule is there, above Images, with its patterns visible and
> editable. Delete it, quit, relaunch — it must stay deleted.

That last sentence is the migration marker's whole promise, and nothing automated can check it.
