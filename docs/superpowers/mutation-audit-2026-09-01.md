# Filing by filename — what the tests were shown to catch

Companion to `docs/superpowers/specs/2026-09-01-ledge-name-patterns-design.md`
and its plan. Written while the runs were still on screen.

This project's rule is that a test must be demonstrated to fail against the
defect it was written for. This file records that those demonstrations happened,
what they showed, and — as often — where the plan's prediction about them was
wrong.

Thirteen commits, `8883c41..c6b4d17`. 280 tests at the end, from 248 at the
start. `make build` and `make strings` (three checks) clean throughout.

## Per task

| Task | What it added | Mutations run | Divergence from the plan's prediction |
|---|---|---|---|
| 1 | `Glob.matches` | 5 | 1 — see below |
| 2 | `Category.namePatterns`, `matches`, decoder | 5 | 1 |
| 3 | `Categorizer` asks the category | 4 | none |
| 4 | `Screenshots` rule, marked migration, `noConditions` | 8 | 1 |
| 5 | `namePatternsField` / `parseNamePatterns` | 5 | 1 |
| 6 | The editor field | — | app target has no tests |
| 7 | The launch hook | — | app target has no tests |

Four of the five predictions that missed were the plan naming **more** tests
than a mutation actually kills, or **fewer**. Every one turned out to be an
error in the plan rather than a gap in coverage — in each case the mutation
still killed something, which is the property that matters. They are recorded
because a mutation table that is quietly wrong is a mutation table nobody will
trust the next time.

- **Task 1.** "Delete the trailing-star cleanup → two tests fail." Only one
  does: `report*.pdf` resolves its star by mid-loop backtracking and never
  reaches that line, which matters only for `*` against an empty name.
- **Task 2.** "Drop the `!extensions.isEmpty` guard → one test fails." Two do;
  both fixtures use `extensions: []`.
- **Task 4.** "Delete the marker assignment → two tests fail." One does; the
  other returns through the early guard before reaching that line.
- **Task 5.** "Split on whitespace too → two tests fail." Five do; most fixtures
  contain an internal space.

## The one real gap, found by the final review

Spec §2's most-argued decision — fold case with `lowercased()` and never
`lowercased(with: Locale.current)`, because a Turkish locale maps `I` to `ı` —
**shipped pinned by nothing.** Mutating that line left all ten `Glob` tests
green: every fixture matched case on both sides, so both foldings agree in
every locale.

`foldingIsLocaleIndependentForTheTurkishDottedI` closes it, and the
demonstration took real work. Environment variables do not move `Locale.current`
on macOS; only a process argument does, and `swift test` exposes no way to pass
one. The fix traced `swift test`'s child invocation, replayed
`swiftpm-testing-helper` directly with `-AppleLocale tr_TR`, and measured:

| Glob.swift | Locale | Result |
|---|---|---|
| mutated to `lowercased(with:)` | default | 280 pass |
| mutated to `lowercased(with:)` | `tr_TR` | the new test fails, alone |
| as shipped | `tr_TR` | 280 pass |

A re-reviewer reproduced all three rows independently rather than reading the
narrative. That second run is the reason this entry is here as evidence rather
than as a claim.

## What ships untested

The app target has no tests, by design — every decision in this feature lives in
`LedgeCore`. Untested and known to be so:

- the migration trigger in `AppState.init`. Deleting that block leaves all 280
  tests green and the feature silently never reaches an existing user. It is the
  highest-value unguarded line on the branch, and `docs/manual-checks.md` §10 is
  its only guard.
- the patterns field, `tidyPatterns()`, and the focus wiring.

Nothing visual has been seen by anyone. No agent on this project has had Screen
Recording or Accessibility permission.
