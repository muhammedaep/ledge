# Known limitations

Written at the end of the first build, while the reasons were still legible. Each
of these was found, understood, and deliberately left — none is a surprise waiting
to be discovered.

## The app target has no tests

`LedgeCore` holds every decision the app makes and has 235 tests, mutation-audited:
each was demonstrated to fail against the bug it was written to catch. The app
target — `AppState`, the views — has none, because it sits outside the SPM package
and no test target exists for it.

Two guards live there with no automated coverage:

- **`filingRoot`** (`AppState.swift`), which decides whether a download goes to the
  active project or the folder it was found in. Fails safe: it falls back to the
  found-in folder.
- **`isOrganizing`** (`AppState.swift`), the re-entry guard that stops a second
  Organize Now pass starting over a folder still moving. Fails safe: it refuses
  rather than queues.

Both were verified by hand during the build, with harnesses that compiled the real
`AppState` and measured it. Those harnesses died with the session; the guards did
not gain permanent tests.

The honest fix is an app-level test target. It is a task, not a patch — adding one
in a hurry is how a clean branch acquires a rushed harness.

Three rules were lifted out of the app target during the build for exactly this
reason (the self-filing guard, project identity, extension parsing), so the pattern
is established: **if it is a rule, it belongs in `LedgeCore` where it can be
tested.** These two are orchestration and cannot move.

## `LedgeSupportDirectory` is not injectable

All three stores resolve `~/Library/Application Support/Ledge` through
`FileManager.urls(for: .applicationSupportDirectory, …)`, which nothing can
redirect except the `CFFIXED_USER_HOME` environment variable.

This caused two incidents during the build: verification harnesses wrote into the
real support directory believing they were isolated, because overriding `HOME`
does not redirect that API. Both times the agent involved was reasoning correctly
about residue it had itself created.

Injecting the directory would also close the one test gap in `MoveJournal` —
`applicationSupport(cap:)` is currently untestable under this project's own rule
that no test may touch `~/Library`.

**Do this before anyone writes another harness.**

## Errors share one slot

`AppState.lastError` is a single value. A watcher failure arriving before the user
opens the shelf will overwrite an earlier notice — for instance, a corrupt-rules
message they never saw.

The banner is visible in every state, including behind the permission screen, so
nothing is silent. But the most recent message wins, and there is no history.

## The batch outcome is only visible from the Organize sheet

If an Organize Now batch finishes while no window is open, the moved files appear
in Recent Downloads but nothing announces that a batch completed. The undo
affordance for it surfaces only on reopening Organize Now.

This is how it was designed rather than a regression — batch undo was always
sheet-scoped — but it is worth knowing.

## ⌘Z is inert while the Organize sheet is key

That sheet owns its own batch-undo button. The spec does not say either way, so
this was a judgement rather than a requirement.

## The reconnect poll is a poll

A watched folder that disappears is re-checked every 500 ms until it returns. The
timer runs **only** while something is actually unavailable, which is the whole
battery win — but note that `leeway` does not help here: Dispatch clamps it for
repeating timers and applies it only to the first deadline. That was measured.

## What has not been seen by anyone

Not quite everything visual, in the end. No agent that built this had Screen
Recording or Accessibility permission, and for most of the build the working
assumption was that nothing rendered could be checked without them. That
turned out to be too strong: `ImageRenderer` renders a SwiftUI view off-screen
and its pixels can be read back, with no screen permission of any kind needed.
Three tasks used it to settle colour questions that reasoning had gotten
wrong — twice, a conditional style shipped rendering two states that were
supposed to differ in the identical grey, and it was the pixel comparison that
caught it, not a second reading of the code.

What that technique cannot reach is everything else: layout, spacing, whether
Turkish text fits its frames, whether the panel's cross-display frame jump
when the Organize sheet attaches reads as a glitch. That narrower set is the
real unverified-as-rendered list, and it is not shrunk by the above.

`docs/manual-checks.md` is the list. The drag-out itself was confirmed by hand
early on; nothing else on it was.

## One test is flaky, and the product code is not at fault

`aFileReplacedByADanglingSymlinkMidSettleIsNotIgnored`
(`DownloadSettlerTests.swift:476`) fails roughly one run in six. It was flaky
before the visual-design branch, which touches neither the settler nor its
tests.

The cause is in the test, not in `DownloadSettler`. The test simulates a file
being *replaced* by a dangling symlink using two calls:

```swift
try FileManager.default.removeItem(at: file)
try FileManager.default.createSymbolicLink(...)
```

Between them the path does not exist at all. The settler samples every 50 ms,
and when a sample lands in that window it returns `.ignored` — which is the
right answer to what it actually saw. The guard being tested
(`DownloadSettler.swift:88`, `FileEntry.exists` rather than `fileExists`, so a
dangling link counts as present) is correct and is doing its job; the test just
does not present it with the atomic replacement it claims to.

The fix is to make the swap atomic — build the link at a sibling path and
`replaceItemAt` — which belongs in a change to the settler's tests, not in a
branch about the interface. Until then, a red run of this one test is a
re-run, not a regression.

## `ImageRenderer` cannot see the appearance setting

The off-screen render this project leans on for colour evidence draws without
a window, so it never picks up `NSApplication.shared.appearance`. Asked
whether the Appearance setting changes a dynamic colour, it answers "no" for
both light and dark — a false negative that would send the next person to
rewrite a feature that works.

What does answer it: make a real `NSWindow`, set the app appearance, and read
`view.effectiveAppearance` inside
`performAsCurrentDrawingAppearance`. Measured that way, light resolves to the
light branch and dark to the dark one, which is how the setting was verified.

`ImageRenderer` stays the right tool for "do these two states differ in
colour" inside one appearance. It is the wrong tool for anything that depends
on which appearance is current.

## The journal and the folder lists are trusted

`journal.json`, `projects.json` and the watched-folder list live in
`~/Library/Application Support/Ledge`, and the paths in them are acted on as
written: undo moves `to` back into `from`, the shelf row drags `to` out and
reveals it in Finder, the watcher opens whatever folder the list names. On
load the journal now drops any record whose paths are not file URLs — `URL`
decodes `https://…` without complaint and its `.path` is a filesystem path —
but a record that names two real folders is believed.

The boundary this draws: anything that can write to the user's Application
Support folder can make Ledge move a file between two paths of its choosing,
under Ledge's own Files and Folders grants, behind a row whose name is
whatever the record says. That is the user's own account writing to the
user's own files, which is where every unsandboxed app's trust ends — but
Ledge holds folder grants a lesser process may not, and the confused-deputy
shape is real. The stricter fix, refusing any record whose `to` is not inside
a folder Ledge currently watches or a project it knows, would also silence
undo for every file filed from a folder the user has since stopped watching.
That trade was not taken on the day of the first release; it is recorded here
so it is taken deliberately.

## There is no update mechanism

The first release went out on 2026-09-03 as a Developer ID–signed, notarized
DMG, universal (`lipo` reports `x86_64 arm64`). Nothing in the app checks for
a newer version, downloads one, or tells the user one exists. A new version is
a new DMG the user has to find and install by hand, and until that changes
every release note has to say so. There is no Homebrew cask and no App Store
presence either; `make build` and CI still produce a binary for the machine
that built them, and only `make release` produces the universal one.

## The Rules tab has no drag-to-reorder

The design carries precedence three ways: an ordinal, a drag grip, and the
rubric. Two shipped. Reordering is by the up/down buttons, which work from
the keyboard; the grip was left for a piece of work that can give drop
targets and accessibility the attention they need. Nothing is missing — this
is a second route that does not exist yet.

## The accent colour is pinned

`#0a6cd6` light, `#409cff` dark, rather than `Color.accentColor`. A user who
has set a pink system accent sees the design's blue. That followed from the
instruction that it look exactly like the design, and it is recorded here so
the next person reads it as a decision rather than an oversight.

## A dragged row hands over a copy

The drag out of the shelf puts one thing on the pasteboard, `public.file-url`,
the way Finder's own drags do. SwiftUI's `onDrag` on macOS does not pass that
URL through, though: it copies the file into
`~/Library/Caches/com.apple.SwiftUI.Drag-<UUID>/` and the drop target is
given *that* path — read off the drag pasteboard after a real drop on
2026-09-03. So a row dropped on the Desktop puts a copy there, the filed file
stays where it was, and undo keeps working.

Until that day the row used `NSItemProvider(contentsOf:)`, which also
registers the file's content type as a *file representation*, and the copy
then arrived named `.com.apple.Foundation.NSItemProvider.XXXXXX.pdf` — an
invoice nobody could recognise. The name is right now; the copy is SwiftUI's
and stays.
