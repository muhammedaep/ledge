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

Everything visual. No agent that built this had Screen Recording or Accessibility
permission, so the entire interface is unverified as *rendered* — layout, spacing,
whether Turkish text fits its frames, whether the panel's cross-display frame jump
when the Organize sheet attaches reads as a glitch.

`docs/manual-checks.md` is the list. The drag-out itself was confirmed by hand
early on; nothing else was.

## The build is native-arch only

`make build` and CI produce a binary for the machine that built them. `make
archive` is intended to produce a universal build and has never been run. There is
no notarised release, no Homebrew cask, and no App Store presence — the README says
so, and it should keep saying so until one of those is actually true.
