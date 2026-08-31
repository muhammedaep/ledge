# Mutation audit — LedgeCore, 2026-08-31

Two components in this project were reviewed, approved on behaviour, and then
found to have suites that did not defend that behaviour. In one case a test
written specifically as a guard passed with the very bug it was guarding against
restored. This document is the standing record of which tests actually
discriminate, and what was done about the ones that did not.

It has two parts:

- **Part 1** is the original audit (45 mutations, 11 survivors) as recorded in
  `.superpowers/sdd/2026-08-31-ledge/mutation-audit-core.md`.
- **Part 2** is this task's work: every survivor closed or explicitly justified,
  each new test demonstrated *red* against the mutation it targets before being
  accepted.

**Method.** `git worktree add --detach 98566aa /tmp/ledge-11b-mut`; all mutation
work in that checkout, never in the repository. One mutation applied at a time
via `scratchpad/mutate.py`, the tests that should catch it run, the mutation
reverted. The source repo was never left in a mutated state, and the worktree
was removed afterwards.

**Baseline at `98566aa`: 88 tests. After this task: 107 tests.**

---

## Part 1 — the original audit

45 mutations, 34 killed, 11 survived, 0 failed to compile.

| Component | Mutations | Survived | Survivor IDs |
| --- | --- | --- | --- |
| Categorizer | 9 | 2 | C7, C9 |
| RulesStore | 7 | 2 | R5, R8 |
| FileMover | 10 | 4 | F3, F8, F9, F10 |
| MoveJournal | 8 | 1 | J7 |
| UndoService | 6 | **0** | — |
| DirectorySnapshot | 5 | 2 | D3, D4 |

The killed mutations and the reasoning behind each survivor are in the original
file and are not repeated here. `UndoService` was clean — all six mutations
killed, four by a sole killer — and was left alone.

---

## Part 2 — every survivor, and what was done

Each row's "demonstrated red" is a real run: the mutation applied to the scratch
checkout, the named test run against it, the recorded failure quoted verbatim.
A test with no such demonstration has not been shown to discriminate, which is
the exact failure this task exists to fix.

### Summary

| ID | Component | Status | Closing test |
| --- | --- | --- | --- |
| C7 | Categorizer | **closed** | `customFallbackNameIsHonoured` |
| C9 | Categorizer | **closed by a production fix** | `anyPackageDirectoryMatchesWhenARuleClaimsItsExtension`, `aDirectoryTheSystemDoesNotCallAPackageNeverMatches` |
| R5 | RulesStore | **closed** | `lastLoadWasCorruptClearsOnACleanReload` |
| R8 | RulesStore | **closed — was a real defect** | `eachCorruptLoadGetsItsOwnQuarantineFile` |
| F3 | FileMover | **closed** | `aNameLostToAnOutsideProcessIsRetriedOntoTheNextFreeName` |
| F8 | FileMover | **closed** | `anUnwritableDestinationThrowsDestinationNotWritable` |
| F9 | FileMover | **closed** | `aCollisionThatNeverClearsGivesUpAfterTheRetryBudget` |
| F10 | FileMover | **closed** | `aFailureThatIsNotACollisionIsSurfacedWithoutRetrying`, `isNameCollisionMatchesOnlyTheClobberRefusal` |
| J7 | MoveJournal | **closed** | `anOutOfOrderJournalFileIsSortedOnLoad` |
| D3 | DirectorySnapshot | **equivalent — no test, confirmed independently** | — |
| D4 | DirectorySnapshot | **closed** | `newEntriesFromTwoRealScansOfTheSameFolder`, `scanEntriesMatchURLsBuiltFromTheFolderThatWasScanned` |

**11 survivors: 10 closed by test, 1 confirmed a genuine equivalent mutation.**

---

### C7 — the fallback ignored the user's configured fallback name

Every Categorizer test used a `RuleSet` with the default `fallbackName`, so
hardcoding `"Other"` in both places changed nothing any test observed —
even though `RulesStore.savedRulesAreLoadedBack` proves a custom fallback is
expressible and persisted.

Added `CategorizerTests.customFallbackNameIsHonoured`.

```
Mutation: rules.fallbackName -> "Other" (both occurrences)
✘ customFallbackNameIsHonoured: (result.category → "Other") == "Misc"
✘ customFallbackNameIsHonoured: (result.folder → …/Other) == (…/Misc)
```

### C9 — the bundle allowlist, resolved rather than papered over

The source comment said a directory matches when *a rule* claims its extension.
The code additionally required membership in a hardcoded allowlist (`app`,
`bundle`, `framework`, `photoslibrary`, `aplibrary`). The only test used `app`,
which satisfies both readings, so the suite could not say which was intended.
The user-visible consequence: adding `sketch` to a category in the rules editor
still filed a real Sketch bundle to `Other`.

**Production change.** The allowlist is gone. `FileFacts` gained an `isPackage`
property, read from `URLResourceKey.isPackageKey` in `init?(url:)`, and
`Categorizer` now matches a directory when a rule claims its extension **and**
the system reports the directory as a package. This keeps the behaviour that
made the allowlist exist — a folder merely *named* `footage.mp4` is not a video
— while asking macOS the real question instead of guessing from a list.

Measured directly (`scratchpad/probe.swift`) before committing to it:

```
Thing.app            dir=true package=true
Thing.bundle         dir=true package=true
Thing.framework      dir=true package=false   <- differs from the old allowlist
Thing.photoslibrary  dir=true package=true
Thing.aplibrary      dir=true package=true
Thing.rtfd           dir=true package=true    <- the old list missed this
Thing.sketch         dir=true package=false   (true where Sketch is installed)
footage.mp4          dir=true package=false
My Project           dir=true package=false
plain.png            dir=false package=false
```

**One behaviour change worth flagging:** `.framework` is *not* a package by
macOS's reckoning — Finder lets you walk into one — so a loose `.framework`
folder now routes to the fallback rather than to whichever category claims
`framework`. That is the honest consequence of asking the system instead of
keeping a list, and it is the same mechanism that fixes `sketch`, `rtfd`,
`logicx`, `numbers`, `pages`, and every bundle type an installed app registers.

Added `anyPackageDirectoryMatchesWhenARuleClaimsItsExtension` (parameterised
over `sketch`, `rtfd`, `photoslibrary`, `logicx`) and its converse
`aDirectoryTheSystemDoesNotCallAPackageNeverMatches`. The pair pins the guard in
both directions, so the allowlist cannot come back in either form.

```
Mutation: restore the hardcoded bundleExtensions allowlist
✘ anyPackageDirectoryMatches… [ext → "sketch"]: (result.category → "Other") == "Design"
✘ anyPackageDirectoryMatches… [ext → "rtfd"]:   (result.category → "Other") == "Design"
✘ anyPackageDirectoryMatches… [ext → "logicx"]: (result.category → "Other") == "Design"
✘ aDirectoryTheSystemDoesNotCallAPackageNeverMatches: (result.category → "Apps") == "Other"
```

`photoslibrary` correctly did *not* fire — it is on the old allowlist, so that
argument cannot tell the two readings apart. That is the right outcome, and it
is precisely why the original single-`app` test could not catch C9.

The wiring from disk is pinned separately, in a new `FileFactsTests`:

```
Mutation: FileFacts.init?(url:)  values.isPackage ?? false -> false
✘ factsReadAPackageDirectoryFromDisk: (facts).isPackage → false
✘ routesBundleFoldersByTheirExtension: (plan[0].destination.category → "Other") == "Apps"
```

### R5 — the corruption flag never came back down

`load()` opens with `lastLoadWasCorrupt = false`. Deleting that line makes the
flag sticky: once any load is corrupt, every later load on the same instance
still reports corrupt. No test loaded twice from one store. The consequence is a
"your rules were reset" banner that never clears.

Added `RulesStoreTests.lastLoadWasCorruptClearsOnACleanReload`.

```
Mutation: drop `lastLoadWasCorrupt = false` from the top of load()
✘ lastLoadWasCorruptClearsOnACleanReload: !((store).lastLoadWasCorrupt → true)
```

### R8 — this one was a real defect, not just a coverage gap

The quarantine name is `rules.corrupt-<ISO8601 second>.json` and the rename is
`try?`. Two corrupt loads inside the same second produced the *same* target
name; the second `moveItem` failed, `try?` swallowed it, and the corrupt
`rules.json` stayed in place until the next `save` overwrote it — destroying the
hand edits quarantining exists to preserve.

**Production change.** `quarantine()` now routes the timestamped name through
`FileMover.availableURL(for:in:)`, the codebase's existing "first free name"
answer, so the second rename cannot collide.

Added `RulesStoreTests.eachCorruptLoadGetsItsOwnQuarantineFile`, which asserts
both files survive *and* their contents come back.

Demonstrated red against the mutation **and against the pre-fix production
code**, which is what establishes this was a defect rather than a gap:

```
Mutation R8 (fixed quarantine name):
✘ eachCorruptLoadGetsItsOwnQuarantineFile: (quarantined.count → 1) == 2
✘ …: !(fileExists(…/rules.json) → true)
✘ …: (recovered → ["{ first bad"]) == ["{ first bad", "{ second bad"]

Pre-fix production code (timestamp, no availableURL) — identical failure:
✘ eachCorruptLoadGetsItsOwnQuarantineFile: (quarantined.count → 1) == 2
✘ …: !(fileExists(…/rules.json) → true)
✘ …: (recovered → ["{ first bad"]) == ["{ first bad", "{ second bad"]
```

### F3, F9, F10 — the entire retry mechanism was untested

Three survivors pointed at one thing. The retry loop, documented at length as
"a second line of defense against a collision from outside this process", had
zero coverage: you could delete it (F3), set its bound to zero (F9), or broaden
its trigger to retry on disk-full and permission errors (F10), and the whole
suite passed.

The reason is structural. The `NSLock` serializes every in-process move, so no
in-process caller can ever lose a name race; the retry can *only* fire against a
racer outside the process. Every purely-external construction attempted was a
timing race — the window between `availableURL` and the rename is microseconds
wide, and nothing pre-arranged on disk can clear itself mid-loop, because the
loop makes no filesystem change until it succeeds. (Confirmed en route that the
scenario itself is real, not hypothetical: a *dangling symlink* is reported
absent by `fileExists` while `moveItem` still refuses it with
`NSCocoaErrorDomain 516` — availableURL says free, the rename says taken.)

**Production change.** `FileMover` gained an injected `performMove`, defaulting
to `FileManager.moveItem`. This follows two seams already approved in this
codebase for the same reason — `ScanEngine.factsProvider` and
`DownloadSettler.sizeProvider` — and it lets a test stand in for the rename and
fail it exactly the way a lost race fails. `maxCollisionRetries` and
`isNameCollision` moved from `private` to `internal` so the tests can assert the
loop honours *those* values rather than numbers copied into the test.

Three tests, plus a table test on the predicate:

```
Mutation F3 (remove the `continue`):
✘ aCollisionThatNeverClearsGivesUpAfterTheRetryBudget:
      (attempts.count → 1) == (FileMover.maxCollisionRetries + 1 → 6)
✘ aNameLostToAnOutsideProcessIsRetriedOntoTheNextFreeName:
      Caught error: .underlying(domain: "NSCocoaErrorDomain", code: 516, …)

Mutation F9 (maxCollisionRetries = 0):
✘ aNameLostToAnOutsideProcessIsRetriedOntoTheNextFreeName:
      Caught error: .underlying(domain: "NSCocoaErrorDomain", code: 516, …)

Mutation F10 (isNameCollision matches any Cocoa error):
✘ aFailureThatIsNotACollisionIsSurfacedWithoutRetrying: (attempts.count → 6) == 1
✘ isNameCollisionMatchesOnlyTheClobberRefusal [640 fileWriteOutOfSpace]:  → true == false
✘ isNameCollisionMatchesOnlyTheClobberRefusal [513 fileWriteNoPermission]: → true == false
✘ isNameCollisionMatchesOnlyTheClobberRefusal [4 fileNoSuchFile]:          → true == false
```

### F8 — `destinationNotWritable` was never asserted by any test

No test made `createDirectory` fail, so the mapping of that failure onto
`MoveError.destinationNotWritable` was unverified; the caller would get a
confusing `.underlying(…)` instead of the specific error the UI needs in order
to say "that folder isn't writable".

Added `FileMoverTests.anUnwritableDestinationThrowsDestinationNotWritable`,
which puts a *file* where the destination folder should be.

```
Mutation: replace the do/catch around createDirectory with `try?`
✘ anUnwritableDestinationThrowsDestinationNotWritable:
      expected error ".destinationNotWritable(…/Images)", but got
      ".underlying(domain: "NSCocoaErrorDomain", code: 512, …)"
```

### J7 — the load-path sort was unverified

`MoveJournal.read(from:)` sorts newest-first after decoding. Returning the
decoded array unsorted survived, because `persist()` always writes an
already-sorted array, so every file the tests produced was already in order. The
sort only matters for a file this code did not write in this shape — a hand
edit, or an older build — which is exactly what it is there for.

Added `MoveJournalTests.anOutOfOrderJournalFileIsSortedOnLoad`, writing the JSON
directly rather than through `append`.

```
Mutation: read(from:) returns `records` instead of `records.sorted { … }`
✘ anOutOfOrderJournalFileIsSortedOnLoad:
      (records.map(\.originalName) → ["old.png", "new.png"]) == ["new.png", "old.png"]
```

### D3 — genuinely equivalent; no test written, and none should be

The audit recorded this as an equivalent mutation. Re-checked independently
rather than taken on trust, and it holds: `.skipsSubdirectoryDescendants` is a
no-op for `contentsOfDirectory(at:includingPropertiesForKeys:options:)`, which
is shallow by nature — the option only means anything to `enumerator(at:)`.

Direct measurement against a fixture containing `nested/deeper/`, a top-level
file and a hidden file (`scratchpad/probe.swift`):

```
both:        ["nested", "top.png"]
no skipsSub: ["nested", "top.png"]     <- byte-identical
no skipsHid: [".hidden", "nested", "top.png"]
neither:     [".hidden", "nested", "top.png"]
```

And the mutation applied against the *whole* hardened suite:

```
✔ Test run with 107 tests in 0 suites passed
```

There is no compiling variant that changes behaviour, because the flag changes
no behaviour to begin with. **No test added.** The option stays as a signpost
for anyone tempted to swap in an enumerator, with a comment on
`DirectorySnapshot.init(scanning:)` saying exactly that — and noting that
`scanningReadsTopLevelEntriesOnly` guards the API's shallowness, not the option.

### D4 — the scan/diff seam, the most consequential gap in the audit

`init(scanning:)` maps every entry through `.resolvingSymlinksInPath()`.
Removing it survived all 88 tests, because the suite was split cleanly in half:
the diff tests used hand-built `DirectorySnapshot(entries:)` fixtures, the scan
tests compared only `lastPathComponent`, and **no test ever diffed two real
scans** — the one thing the type exists to do.

The normalization is emphatically not cosmetic. Measured
(`scratchpad/probe2.swift`): handed a folder under `/var/…`,
`contentsOfDirectory` returns its contents under `/private/var/…`. `entries` is
a `Set<URL>` and `URL` equality is path-string equality, so without
normalization every entry is a different key from the one any caller would build
for the same file.

Added two tests: `newEntriesFromTwoRealScansOfTheSameFolder`, which diffs two
real scans and closes the seam, and
`scanEntriesMatchURLsBuiltFromTheFolderThatWasScanned`, which pins the
normalization itself on whole URLs rather than names.

```
Mutation: Set(contents.map { $0.resolvingSymlinksInPath() }) -> Set(contents)
✘ newEntriesFromTwoRealScansOfTheSameFolder:
      (after.newEntries(comparedTo: before) → [file:///private/var/…/new.png])
      == ([added.resolvingSymlinksInPath()] → [file:///var/…/new.png])
✘ scanEntriesMatchURLsBuiltFromTheFolderThatWasScanned:
      (entries → [file:///private/var/…/second.png, file:///private/var/…/top.png]) == …
```

An earlier attempt to express this through a symlinked folder was abandoned on
evidence: `contentsOfDirectory(at:)` refuses a symlink-to-directory outright
(`NSCocoaErrorDomain 256`), so that fixture tested nothing.

---

## Tests that passed for the wrong reason

These had no surviving mutation of their own, but the audit showed they could
not observe what their names claimed.

### `firstMatchingCategoryWins` could not fail

C3 replaced `first(where: { $0.extensions.contains(ext) })` with `first` — the
exact "stop filtering, take the head" defect the test exists to prevent — and
**the test passed**. Both categories in its fixture claimed `png`, so "first
matching" and "first, period" gave the same answer. The ordering guarantee that
the `RuleSet` doc comment calls "what makes the order user-editable and
meaningful" was defended only by an unrelated fallback test.

Fixed by making the head of the list claim nothing relevant, and adding a third
category after the intended winner so the test also fails on "last match wins":

```
Mutation C3: first(where: …) -> first
✘ firstMatchingCategoryWins: (…category → "Design") == "Images"
```

### The overwrite guard killed only 11 runs in 12

`concurrentMovesToTheSameNameAllSucceedInsteadOfThrowing` is the only guard
against a *silent overwrite* — the one failure mode in this codebase that
destroys a user's file rather than misplacing it — and with the `NSLock`
removed it went green on run 9 of 12. A passing run was not evidence the lock
was there.

The audit suggested repeating the race in-test. **Repetition was not the choice
made**, for two reasons: it multiplies runtime to buy a probability that is
still not 1, and it leaves the underlying cause — a race window microseconds
wide, entered only if the scheduler cooperates — untouched. Two changes make it
deterministic instead:

1. **The window is widened on purpose.** The injected `performMove` pauses 20ms
   between `availableURL` choosing a name and the rename landing on it. With the
   lock, movers queue and the pause costs nothing; without it, all eight choose
   the same name before any of them acts.
2. **Real threads released from a barrier, not `DispatchQueue.concurrentPerform`.**
   GCD caps concurrent iterations at the core count, and with fewer than seven
   movers genuinely overlapping, the retry budget absorbs the collisions and
   hides a missing lock. Blocked threads cost nothing, so eight OS threads
   overlap on any machine.

Re-measured with the lock removed, twelve consecutive runs:

```
killed 12/12  ['KILLED' × 12]
✘ concurrentMovesToTheSameNameAllSucceedInsteadOfThrowing:
      (names → ["a (1).png", "a (2).png", "a (3).png", "a.png"])
      == (expected → ["a (1).png" … "a (7).png", "a.png"])
```

Four of eight files silently destroyed, every run. That is the failure this test
exists to report, and it now reports it every time.

### `journalSurvivesReload` asserted only a count

`records.count == 1` verifies that *a* record came back, not that it is *the*
record — and `batchID` was never asserted to survive a reload anywhere in the
suite, leaving "quit the app, reopen it, undo the Organize Now batch you just
ran" untested end to end. Now asserts whole-record equality.

```
Mutation: read(from:) drops batchID while reconstructing records
✘ journalSurvivesReload: (records → [… batchID: nil]) == ([original] → [… batchID: B7AE…])
```

Noted in passing, not a defect: the journal encodes dates as ISO8601, which has
second resolution, so a persisted `Date` does not round-trip below the second.
The test uses a whole-second date deliberately.

### `corruptFileIsQuarantinedAndDefaultsRestored` never checked the contents

It asserted only that a `rules.corrupt-` file existed. The stated purpose of
quarantining — "so a user who hand-edited it can get their work back" — was
unverified: a quarantine that created an empty file would have passed.

```
Mutation: quarantine writes an empty file and deletes the original
✘ corruptFileIsQuarantinedAndDefaultsRestored: (recovered → "") == "{ this is not json"
```

### `fallbackIsNeverSubdivided`, `newJournalIsEmpty`, `corruptJournalFileLoadsAsEmpty`

Left as they are. Each is structurally unable to fail while its neighbour
passes, and each would pass against a stub. They are documentation rather than
guards; they are harmless, and they should not be counted as coverage.

---

## Folded in from other tasks

### Task 9 — `DownloadSettler`

**A read claim was being answered with a write claim.** Changing
`readingIntent(…, .withoutChanges)` to `writingIntent(…, [])` survived the
suite. Ledge would take a *write* claim on the user's file merely to ask whether
it was readable, blocking every other reader of a document it had only been
asked to look at.

Added `aFileAnotherAppIsOnlyReadingIsReady`, which holds a real *reading* claim
on a background thread and asserts the settle is unaffected by it.

The first version of this test asserted `elapsed < 300ms` — real code ~0.02s,
mutant ~1.0s — and that assertion was **withdrawn as untrustworthy**. Measured
in this suite, a coordinated read with nothing whatsoever contending has taken
0.7–0.8s under load, so a stopwatch threshold here reports load, not behaviour.
The test now asserts an *ordering fact* instead: the reader's claim is held
until the settle returns, and the test checks that the settle finished while the
claim was **still held**. A settle that ignores a read claim finishes inside it;
one that waits for it cannot. A 5s backstop releases the claim regardless, so a
mutant fails rather than hangs.

```
Mutation: readingIntent(with:options:.withoutChanges) -> writingIntent(with:options:[])
✘ aFileAnotherAppIsOnlyReadingIsReady: (claimHeld).isRaised → false
   failed after 5.015 seconds   [the backstop, i.e. it waited out the whole claim]

Unmutated, three consecutive runs against the loaded tree: 0.037s, 0.036s, 0.035s — passed.
```

**A suite that hangs is worse than one that fails.** Never resuming the
continuation on the error path does not fail the suite — it hangs it (>90s,
killed by hand), reporting nothing at all. Both cancellation tests now carry
`.timeLimit(.minutes(1))`, the coarsest granularity Swift Testing allows.

**The `.cancelled` doc comment overstated.** A settle cancelled inside the
coordinated read returns `.stillWriting`, not `.cancelled`. **The comment was
fixed, not the value**: cancelling the coordinator fails the pending read, and a
failed coordination is indistinguishable from a claim genuinely lost, so the
conservative answer is the right one. Both outcomes tell the caller the same
thing — do not move it, ask again later — which is why the distinction does not
warrant a fifth case.

### Task 11 — `ScanEngine`

Dropping the `.sorted` call survived: no test pinned plan order beyond
single-element or `Set`-based comparisons. Order matters for the stability of a
preview list a user reads and re-reads while deciding, not for correctness.

Added `planIsOrderedByFileName`, six entries written in an order that is not the
answer — an unsorted plan matching by luck is a 1-in-720 event.

```
Mutation: drop `.sorted { $0.source.lastPathComponent < $1.source.lastPathComponent }`
✘ planIsOrderedByFileName:
      (plan.map(\.source.lastPathComponent)
        → ["foxtrot.png", "alpha.png", "bravo.mp4", "delta.png", "echo.png", "charlie.mp4"])
      == ["alpha.png", "bravo.mp4", "charlie.mp4", "delta.png", "echo.png", "foxtrot.png"]
```

---

## Not covered, and honestly so

- **`RulesStore.save` uses `options: .atomic`.** Dropping it is undetectable by
  any unit test that can be constructed — a torn write requires a crash
  mid-write. The line carries a comment so a future refactor does not
  "simplify" it away.
- **`FolderWatcher` and its tests** were out of scope for this task and were not
  touched.

## One pre-existing test is failing, and it is not from this work

`DownloadSettlerTests.aStableFileIsReady` (from Task 9) asserts
`elapsed < 80ms` around a 50ms sample — 30ms of slack. It now fails
consistently in the shared tree, at 0.72–0.90s.

Bisected rather than assumed:

| Tree | Result |
| --- | --- |
| This task's changes, `FolderWatcher` pristine at `98566aa` | **107 tests, 5/5 runs green**, suite 0.85s |
| The same, plus the in-flight `FolderWatcher` work from the shared tree | `aStableFileIsReady` **fails 3/3**, suite 3.2s |

The new watcher tests roughly quadruple the suite's runtime, and that test's
budget cannot absorb the load. The fix belongs with whoever owns that round —
either widen the budget or, better, rebuild the assertion on something other
than a stopwatch, the way `aFileAnotherAppIsOnlyReadingIsReady` above was. Left
untouched here deliberately: `FolderWatcher` is another agent's scope.

A second, intermittent failure was seen once in the same tree,
`watcherDoesNotReemitFilesAfterFolderReappears`, observing sandbox
atomic-write temp files (`pre-existing.png.sb-684a1d85-F71cZb`) as if they were
user files. Also that round's to own; recorded here only because it was seen.

## Production changes made under this audit

Every one of these exists because a surviving mutation revealed something real,
and each is covered by the tests listed above.

| File | Change | Why |
| --- | --- | --- |
| `Rules/FileFacts.swift` | new `isPackage`, read from `URLResourceKey.isPackageKey` | C9 |
| `Rules/Categorizer.swift` | matches a directory on `isPackage`, not a hardcoded allowlist; comment now matches the code | C9 |
| `Rules/RulesStore.swift` | `quarantine()` routes through `FileMover.availableURL` | R8 — a real defect |
| `Moving/FileMover.swift` | injected `performMove`; `maxCollisionRetries` and `isNameCollision` made `internal` | F3, F9, F10, and the F2 reliability fix |
| `Watching/DirectorySnapshot.swift` | comments recording which option is load-bearing and which is a signpost | D3, D4 |
| `Watching/DownloadSettler.swift` | `.cancelled` doc comment corrected | Task 9 |
