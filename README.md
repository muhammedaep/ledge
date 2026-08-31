# Ledge

**Ledge files your downloads into typed folders the moment they land — and
keeps the recent ones one click away in the menu bar, still draggable into
whatever you're working in.**

Rule-based organizers file things away and break the habit of grabbing what you
just downloaded from the Dock. Shelf apps keep it reachable but leave the folder
a mess. Ledge does both.

It was written against a real `~/Downloads`: 1,504 items and 37 GB in one flat
directory.

> **Status: not released yet.** There is no signed build, no notarized DMG, no
> Homebrew cask, and nothing on the App Store. Today the way to run Ledge is to
> [build it from source](#building). See [Installing](#installing) for what that
> means on first launch.

## What it does

- **Files automatically.** A finished download lands in `Images/`, `Videos/`,
  `Documents/` and so on, by extension. Ledge waits until the file has actually
  finished writing before it touches it.
- **Keeps it reachable.** The menu bar shelf lists recent downloads with where
  each one went. Drag a row straight into Slack, Finder, or Premiere — the drag
  carries the real file, from wherever it was filed.
- **Undoes anything.** One click puts a file back where it was found.
- **Cleans up an existing mess.** *Organize Now* shows you what it would move
  before it moves anything, and the whole batch undoes as a single action.
- **Files into the project you're working on.** See below.

## Project mode

Pick a folder as the active project and, while it stays active, downloads are
filed **into that folder** instead of into Downloads — using the same rules, so
the project grows the same `Images/`, `Documents/` subfolders.

This is the feature that came from an actual chore: collecting twenty-five files
into a project folder by hand, one download at a time. With a project active you
just download them.

The active project is chosen from the shelf's *Filing into:* menu, or from
Settings. Switching back is the same menu. If the project folder goes away —
deleted, or on a volume that got unmounted — Ledge files into the watched folder
instead and says so. It never recreates a folder you removed.

## Two guarantees

These are the two promises Ledge actually enforces, and both are covered by
tests that were checked against the bug they exist to catch:

**It never overwrites.** If `report.pdf` is already in the destination, the
arriving file becomes `report (1).pdf`. Not sometimes — every filing path in the
app goes through one mover, which serializes the "pick a free name, then move
onto it" step process-wide, because picking a name and acting on it are not one
atomic operation and two moves racing for the same name can otherwise both
succeed, with the second silently replacing the first.

**It never descends into a folder.** A folder is moved whole or not at all.
Ledge never walks into one to sort its contents, so a project folder, a cloned
repo, or an unzipped download stays intact. A directory is only ever filed by
extension when macOS itself reports it as a package (a real `.app`, a real
`.sketch` document) — so a folder merely *named* `footage.mp4` is not a video,
and goes to `Other/` in one piece.

## Undo

Every move is journaled, so undo is exact: the file goes back to the folder it
was found in, under its original name.

Undo is a move like any other, so it inherits the never-overwrite guarantee —
restoring into a folder that has since gained a same-named file produces a
numbered name rather than clobbering it.

**If the file has moved since**, Ledge does not guess. When the file is no
longer where the journal recorded it — you moved it in Finder, renamed it, or
deleted it — the shelf row shows *Moved or deleted* and undo declines rather
than acting on a path it can no longer vouch for. Undoing an *Organize Now*
batch skips those records and restores the rest, instead of aborting the whole
batch. A skipped record stays in the journal, so if the file comes back (out of
the Trash, or resynced by iCloud or Dropbox) it is still individually undoable.

## Requirements

macOS 14.0 (Sonoma) or later.

`make build` and CI produce a binary for the architecture of the machine that
built it. `make archive` is intended to produce a universal build — Apple
Silicon and Intel — but it has not been run yet, so treat that as unverified
until someone cuts the first release and checks it.

Ledge lives only in the menu bar; there is no Dock icon and no main window.

### Permissions

`~/Downloads` is protected by macOS, so the first launch asks for access. Until
it is granted Ledge can't see anything, and it tells you that on a permission
screen naming the folder rather than sitting in the menu bar looking healthy and
filing nothing. Access is granted in System Settings → Privacy & Security →
Files and Folders.

## Installing

There is no release build yet. Until there is, [build from source](#building) —
an app you built yourself opens normally, with no Gatekeeper prompt and nothing
to click past. Gatekeeper gates on the quarantine flag that a *browser* attaches
to a download, and a local build never has one.

That changes the day there is something to download. An unsigned or
ad-hoc-signed release, fetched from a browser, will be refused on a normal
double-click: **right-click the app → Open**, then confirm, once — after that it
opens normally. A notarized release needs none of that, which is the point of
notarizing it.

The release path is written and checked in (`make dmg`, `make notarize`); it
just hasn't been run, because the Apple Developer Program enrolment behind it is
still activating.

## Configuration

Everything is in Settings, reachable from the shelf.

**General** — automatic filing on and off, launch at login, which folders to
watch, your projects, and how many items the shelf keeps.

**Rules** — the categories and the extensions that belong to each, in priority
order. The order is the rule: the first category claiming an extension wins.
Each category can subdivide its folder by extension (`Images/PNG/`) or by month
(`Images/2026-08/`), or not at all.

The defaults are Images, Videos, Audio, Documents, Archives, Apps, Design,
Fonts and Code, with anything unmatched going to `Other/`.

Rules, projects and the move journal live in
`~/Library/Application Support/Ledge/`.

## Building

```
git clone <this repo>
cd ledge
cd LedgeCore && swift test    # the full suite, headless, no Xcode account needed
```

Then open `Ledge.xcodeproj` in Xcode and run the `Ledge` scheme.

There is a `Makefile` for the same things:

```
make test     # cd LedgeCore && swift test
make build    # compile the app, unsigned
make strings  # check every UI string is in the Turkish catalog
make help     # everything else, including the release targets
```

**If you add or change UI text, run `make strings`.** The interface is localized
into Turkish, and `xcodebuild` — unlike Xcode's GUI — does not write newly
discovered keys back into `Ledge/Resources/Localizable.xcstrings`. Without that
check a new `Text("…")` renders in English under Turkish forever and nothing
says so. It compares what the compiler actually extracted against the catalog
and fails on anything missing, so CI catches it on the pull request. It reads
the compiler's own extraction rather than grepping the sources, which is what
lets it see `.help()` tooltips, hidden `Picker` labels and bare
`Text("\(count)")`.

**No third-party dependencies.** Not in the app, not in the package, not in CI.

The project is split in two. `LedgeCore` is a dependency-free Swift package
holding every decision the app makes — rules, categorization, settling, moving,
journalling, undo — and it runs headlessly under `swift test`. The Xcode target
is a thin SwiftUI layer over it. That split is why the interesting behaviour is
testable without launching an app or touching a real Downloads folder; every
test that hits the filesystem works in its own temporary directory.

## Contributing

Rule suggestions are especially welcome. If Ledge files something into the wrong
category, open an issue or send a change against `RuleSet.defaults`.

One thing to know before sending a test: **this project holds tests to the
standard that they must demonstrably fail against the bug they were written to
catch.** A test that passes whether or not the code is correct is worse than no
test, because it reports a safety that isn't there.
`docs/superpowers/mutation-audit-2026-08-31.md` is the standing record of which
tests were checked that way, which ones did not discriminate, and what was done
about them — including one guard that passed with the exact bug it was guarding
against restored. New tests for core behaviour are expected to meet the same bar.

`.github/workflows/ci.yml` runs the suite and builds the app on every pull
request and every push to `main`.

## License

MIT — see [LICENSE](LICENSE).
