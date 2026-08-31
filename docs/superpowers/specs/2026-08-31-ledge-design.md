# Ledge — Design Document

**Date:** 2026-08-31
**Status:** Approved for planning

---

## 1. Problem

macOS files every download into a single flat `~/Downloads`. Over time it becomes
unusable — the reference case that motivated this project had 1,504 items and 37 GB
in one directory.

Existing tools force a bad trade:

- **Rule-based organizers** (Hazel and similar) file downloads away automatically, but
  the moment a file is filed it disappears from the Dock's Downloads stack. The habit of
  "grab the thing I just downloaded and drag it into the app I'm working in" breaks.
- **Shelf apps** (Dropover, Yoink) preserve drag-out convenience but do no filing.

Ledge does both: files downloads into typed folders immediately, and keeps a menu bar
shelf from which the most recent downloads stay draggable regardless of where they were
filed.

## 2. Goals

- Automatically file new files in watched folders into typed category folders.
- Keep the last N downloads draggable from a menu bar shelf, showing where each went.
- Let the user edit categories and extension rules in-app, without touching a text file.
- Undo any automatic move.
- Organize an existing, already-messy folder on demand, with a preview before anything moves.
- Ship as a native, dependency-free macOS app small enough to feel invisible.
- Be a well-formed open source project: MIT, English source and docs, Turkish UI localization.

## 3. Non-goals (v1)

- Content-based rules (OCR, EXIF, file contents). Extension and basic file metadata only.
- Cloud sync of settings.
- iOS / iPadOS companion.
- Mac App Store distribution (drives the sandboxing decision below).
- Renaming files. Ledge moves files; it never rewrites their names except to avoid a collision.

## 4. Decisions taken during design

| Question | Decision | Rationale |
| --- | --- | --- |
| How is drag-out preserved? | Menu bar shelf | No timers, no ambiguity about where a file is. Works regardless of destination. |
| How configurable are rules? | In-app rules editor | User explicitly chose this over a JSON-only config. |
| Sandboxed? | No | GitHub/Homebrew distribution, not App Store. Sandboxing would add security-scoped bookmark management for no benefit here. |
| Process model | Single process | The shelf requires the app to be running anyway; a separate daemon buys nothing. |
| Language | English source + UI, Turkish localization | Open to international contribution; author still gets a Turkish UI. |
| Dependencies | None | Apple frameworks only. Keeps the binary ~2–3 MB and the build trivial. |

## 5. User experience

### 5.1 Automatic filing

1. A file lands in a watched folder.
2. `DownloadSettler` waits until the file is finished (see §7.2).
3. `Categorizer` maps it to a destination.
4. `FileMover` moves it, never overwriting.
5. The move is appended to `MoveJournal` and pushed onto the shelf.

No notification banner. The menu bar icon briefly animates; that is the only feedback.

### 5.2 The shelf

Clicking the menu bar icon opens a window-style popover:

```
┌────────────────────────────────┐
│  Recent Downloads              │
├────────────────────────────────┤
│  ▶ rapor.pdf          2 min  ↩ │
│     Documents/PDF              │
│  ▶ logo.png           8 min  ↩ │
│     Images/PNG                 │
├────────────────────────────────┤
│  Organize Now…   Open   ⚙      │
└────────────────────────────────┘
```

- Each row is draggable; dragging deposits the real file into the drop target.
- `↩` undoes that single move, returning the file to where it was found.
- Clicking a row reveals it in Finder.
- Rows persist across launches and are capped at a user-set count (default 10).
- A row whose file no longer exists at the recorded path is shown dimmed, is not
  draggable, and has its undo disabled; tapping it does nothing.
  *Amended during implementation (plan amendment A10): this originally offered a
  "Locate…" affordance opening Finder at the parent folder. That is precisely the
  folder the file is no longer in, so the button would have sent the user
  somewhere useless. It was cut rather than built.*

### 5.3 Organize Now

For a folder that is already a mess. Runs `ScanEngine` in dry-run, then shows a preview
grouped by destination with per-group checkboxes and a total count. Nothing moves until
the user confirms. Every move goes through the same `FileMover` and `MoveJournal`, so the
whole batch is undoable.

Directories inside the scanned folder are moved as single units, never descended into.
This is a hard rule: a project folder must never be split apart.

### 5.4 Settings

Two panes.

**General** — launch at login, enable/disable automatic filing, watched folders list
(add/remove), shelf size.

**Rules** — an editable table of categories and their extensions, reorderable (order
determines match priority), with add/remove for both categories and extensions. Each row
also carries that category's subdivision mode (none / by extension / by month), since
subdivision is a per-category property, not a global switch. A "Reset to defaults" button.

## 6. Architecture

Single process. Each module has one responsibility and a narrow interface; only
`FileMover` and `FolderWatcher` touch the filesystem in anger, which keeps the rest
trivially testable.

```
Ledge.app  (MenuBarExtra, style: .window)
│
├─ Watching/
│   ├─ FolderWatcher        FSEvents stream per watched folder
│   └─ DownloadSettler      decides when a file is "finished"
│
├─ Rules/
│   ├─ Category             name + extensions + subdivision preference
│   ├─ RuleSet              ordered [Category]; first match wins
│   ├─ Categorizer          (URL, RuleSet) -> Destination      [pure]
│   └─ RulesStore           load/save RuleSet as JSON
│
├─ Moving/
│   ├─ FileMover            collision-safe move; the only mutator
│   └─ MoveJournal          append-only move log; powers Undo
│
├─ Shelf/
│   ├─ ShelfModel           recent entries, derived from MoveJournal
│   └─ ShelfView            draggable SwiftUI list
│
├─ Organize/
│   ├─ ScanEngine           folder -> [PlannedMove]            [pure-ish: reads only]
│   └─ OrganizePreviewView  confirmation sheet
│
└─ Settings/
    ├─ GeneralView
    └─ RulesEditorView
```

### 6.1 Data flow

```
FSEvents ──► FolderWatcher ──► DownloadSettler ──► Categorizer ──► FileMover
                                                        │              │
                                                   (RuleSet)           ▼
                                                                  MoveJournal
                                                                       │
                                                                       ▼
                                                                  ShelfModel ──► ShelfView
```

`ScanEngine` joins the same pipeline at `Categorizer`, producing a batch of
`PlannedMove` values that the preview sheet filters before handing them to `FileMover`.

> **As built.** Two boxes above were never created as separate types.
> `ShelfModel`'s responsibilities live directly in `ShelfView` and `AppState`
> (`recentRecords`, `refreshRowStatus`), and `FolderWatcher` is a concrete type
> with no protocol in front of it — nothing needed a second implementation, so
> the seam would have been ceremony. `OrganizePreview` was added in `LedgeCore`
> to hold the preview's grouping, which this diagram does not show.

## 7. Component specifications

### 7.1 FolderWatcher

Wraps one `FSEventStreamRef` per watched folder, non-recursive (`kFSEventStreamCreateFlagFileEvents`,
depth 1 — subdirectories of a watched folder are not descended into).

```swift
public final class FolderWatcher: @unchecked Sendable {
    public init(folders: [URL], onNewEntries: @escaping @Sendable (Set<URL>) -> Void)
    public func start()
    public func stop()
    public private(set) var unavailableFolders: [URL]
}
```

Emits new entries. Does no filtering beyond "this entry is here now and was not before".

> **As built.** No `FolderWatching` protocol exists — nothing needed a second
> implementation. `DispatchSource` directory events replaced FSEvents (plan
> refinement in Task 10), and the type grew a reconnect poll after a deleted
> folder's descriptor was found never to see later events at the same path.

### 7.2 DownloadSettler

A file is considered finished when **all** of these hold:

1. Its extension is not in the in-progress blocklist:
   `crdownload`, `part`, `partial`, `download`, `tmp`, `opdownload`, `!ut`.
2. Its name does not start with `.`.
3. Its size has not changed across two samples 2 seconds apart.
4. It is not currently open for writing by another process, checked via
   `NSFileCoordinator` acquiring a coordinated read; if coordination times out (3 s),
   the file is re-queued rather than moved.

Files that fail check 3 are re-sampled, up to a 5-minute ceiling, after which they are
dropped and logged. This prevents a stalled or resumable download from being filed
mid-flight.

### 7.3 Rules

```swift
struct Category: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String              // folder name, e.g. "Images"
    var extensions: [String]      // lowercased, no dot
    var subdivision: Subdivision  // .none | .byExtension | .byMonth
}

enum Subdivision: String, Codable { case none, byExtension, byMonth }

struct RuleSet: Codable {
    var categories: [Category]    // ordered; first match wins
    var fallbackName: String      // default "Other"
}
```

Defaults ship as: Images, Videos, Audio, Documents, Archives, Apps, Design, Fonts, Code,
Other. The Design and Fonts categories exist because the motivating user works in
After Effects and Premiere (`psd`, `aep`, `prproj`, `ttf`, `otf`).

`Categorizer` is a pure function with no filesystem access:

```swift
struct Destination: Equatable { let folder: URL; let category: String }

func destination(for url: URL, in root: URL, using rules: RuleSet) -> Destination
```

Directories always resolve to the fallback category unless a rule names their extension
(e.g. `.app` under Apps). Extension matching is case-insensitive.

Subdivision behaviour:
- `.none` → `Images/`
- `.byExtension` → `Images/PNG/`
- `.byMonth` → `Images/2026-08/` (from the file's creation date, falling back to
  modification date)

### 7.4 FileMover

The only component that mutates the filesystem.

```swift
protocol FileMoving {
    @discardableResult
    func move(_ source: URL, into folder: URL) throws -> URL   // returns final URL
    func moveBack(_ record: MoveRecord) throws
}
```

Rules:
- Creates the destination folder if missing.
- **Never overwrites.** On collision, inserts ` (1)`, ` (2)`, … before the extension.
- Uses `FileManager.moveItem`; source and destination are inside the same watched tree,
  so this is a rename on the same volume.
- Throws rather than partially completing. A failed move leaves the file untouched and is
  surfaced in the shelf as an error row.

### 7.5 MoveJournal

```swift
struct MoveRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let originalName: String
    let from: URL          // parent folder the file was found in
    let to: URL            // final URL after the move
    let date: Date
    let batchID: UUID?     // set for Organize Now batches, nil for automatic moves
}
```

Append-only JSON file, capped at 200 records (oldest trimmed). Persisted on every write so
the shelf survives a crash or restart.

Undo semantics:
- Single undo moves the file from `to` back into `from`, through `FileMover` (so the
  collision rules still apply — undo never overwrites either).
- `⌘Z` in the shelf undoes the most recent record; for an Organize Now batch it undoes the
  entire `batchID` as one action.
- Undoing a record removes it from the journal.
- If the file is gone from `to`, undo fails with a message and the record is marked stale.

### 7.6 ShelfModel

A view model over the journal's most recent `shelfSize` records, plus liveness (does the
file still exist at `to`?), recomputed when the popover opens.

### 7.7 ScanEngine

```swift
struct PlannedMove: Identifiable { let id: UUID; let source: URL; let destination: Destination }

func plan(folder: URL, using rules: RuleSet) throws -> [PlannedMove]
```

Reads only. Enumerates the folder at depth 1, skips hidden entries and the category
folders themselves, and returns a plan grouped by destination for the preview UI.

## 8. Persistence

| What | Where | Format |
| --- | --- | --- |
| Rules | `~/Library/Application Support/Ledge/rules.json` | JSON, `Codable` |
| Journal | `~/Library/Application Support/Ledge/journal.json` | JSON, `Codable` |
| Preferences | `UserDefaults` | watched folders (bookmark-free paths), shelf size, toggles |
| Launch at login | `SMAppService.mainApp` | — |

No database. Both JSON files are small (journal capped at 200 records) and are written
atomically via `Data.write(to:options: .atomic)`.

## 9. Error handling

- **Permission denied on a watched folder** — the folder is marked unavailable in Settings
  with a button that opens the relevant System Settings pane. Filing is skipped for it;
  other folders keep working.
- **Move failure** — the file stays put. A red row appears in the shelf with the reason.
  Never retried automatically, to avoid a loop against a locked file.
- **Corrupt rules.json** — the file is renamed to `rules.corrupt-<timestamp>.json`,
  defaults are restored, and the user is told once.
- **Watched folder deleted** — the watcher for it stops and the folder is flagged in
  Settings rather than silently dropped.

## 10. Testing strategy

Unit tests run against a temporary directory created per test; no test touches the real
`~/Downloads`.

| Component | Coverage |
| --- | --- |
| `Categorizer` | extension matching, case-insensitivity, priority order, all three subdivision modes, fallback, directories |
| `FileMover` | happy path, collision numbering (repeated), missing destination folder, failure leaves source intact |
| `MoveJournal` | append, cap trimming, round-trip encode/decode, batch grouping |
| Undo | single, batch, collision on the way back, stale record |
| `ScanEngine` | plan correctness, hidden files skipped, category folders skipped, directories treated as units |
| `DownloadSettler` | blocklist, size-still-changing, ceiling timeout |
| `FolderWatcher` | integration: create a file in a temp folder, assert a candidate is emitted |

UI is not unit tested. CI runs `xcodebuild test` on macOS via GitHub Actions.

## 11. Distribution

- **Repo:** `ledge`, MIT, English README with screenshots and a GIF of the drag-out.
- **Build:** Xcode project checked in; `xcodebuild` in CI. No package manager needed to build.
- **Release:** signed + notarized `.dmg` attached to a GitHub Release, produced by a
  `make release` script. The author enrolled in the Apple Developer Program on 2026-08-31;
  enrolment can take 24–48 h to activate, so the first release may need to ship
  ad-hoc-signed with a documented right-click → Open step until notarization is available.
- **Homebrew:** a cask in a personal tap initially, submitted to `homebrew-cask` once the
  project has a tagged, notarized release.

## 12. Risks

**R1 — Drag-out from the menu bar may not work as assumed.** `NSMenu` does not support
dragging items out. The design depends on `MenuBarExtra(style: .window)` hosting a real
window in which `.onDrag`/`NSItemProvider(contentsOf:)` behaves normally.

*Mitigation:* this is verified first, before any other code, with a throwaway ~40-line app.
If it fails, the shelf becomes a small always-available floating panel (`NSPanel`,
`.nonactivatingPanel`) summoned from the menu bar icon. Every other module is unaffected,
because nothing below `ShelfView` knows how the shelf is presented.

**R2 — TCC permission friction.** First access to `~/Downloads` triggers a system prompt;
a user who declines gets a silently broken app.

*Mitigation:* detect the failure explicitly and show a first-run screen explaining the
permission, with a button to the right System Settings pane.

**R3 — Filing a file that an app currently has open.** Moving a file out from under
Premiere or Photoshop breaks its link.

*Mitigation:* `DownloadSettler` check 4 (coordinated read). Additionally, Organize Now's
preview lets the user deselect anything they know is in use.

**R4 — Scope.** v1 carries all four optional features the user selected (undo, organize
now, multi-folder, subdivision). This is a full v1, not a minimal one.

*Mitigation:* the implementation plan sequences it so there is a working, useful app after
the shelf and automatic filing land; the rest are additive.

## 13. Project mode

*Added 2026-08-31, during implementation, at the author's request.*

### 13.1 The problem it solves

The motivating user is a video editor. When working on a project, most of what
they download belongs to that project — footage, voiceovers, logos, templates.
Today those files land in `~/Downloads`, get filed by type, and are then moved
by hand into the project folder. This is exactly the chore that produced the
`Copied_Serhat abi` collection: twenty-five files gathered one at a time.

Project mode files them there in the first place.

### 13.2 Behaviour

The user designates a folder as the active project. While a project is active,
new downloads are filed **into that folder** instead of into the watched folder,
using the same rules — so a project gains `Images/`, `Videos/`, `Audio/`,
`Design/` subfolders exactly as `~/Downloads` would.

Only the filing *root* changes. Nothing else does:

- `MoveRecord.from` remains the folder the file was found in (`~/Downloads`), so
  undo still returns the file there. Undo semantics are unchanged.
- The rule set is global. There is no per-project rule set in v1.
- Organize Now still operates on watched folders, not on projects.

### 13.3 Selecting a project

The shelf gains a header row naming the current destination:

```
┌──────────────────────────────┐
│ Filing into:                 │
│ ▸ Summit 2026            ▾   │
├──────────────────────────────┤
│ Recent Downloads             │
│ ▶ logo.png       Images      │
└──────────────────────────────┘
```

The dropdown lists Downloads (the default), every known project, and
"Choose Project…" which opens a folder picker and adds it to the list.

A selection **persists until the user changes it** — no timer. Two things guard
against forgetting it is on:

1. The shelf header always names the destination, at the top, before the file list.
2. The menu bar icon changes shape while a project is active (`folder.fill`
   rather than `tray.and.arrow.down`), so the state is visible without opening
   anything.

A timed auto-expiry was considered and rejected: a long editing session is
exactly when the project stays active longest, so a timer would deactivate it
at the worst moment and produce a "why didn't that download go to the project"
mystery.

### 13.4 Data model

```swift
public struct Project: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String    // defaults to folder.lastPathComponent
    public var folder: URL
}
```

Stored by `ProjectStore` in `~/Library/Application Support/Ledge/projects.json`,
mirroring `RulesStore`. The active project is held as an `activeProjectID: UUID?`
in `UserDefaults`; `nil` means "file into the watched folder", which is the
default and the state after a fresh install.

### 13.5 Failure handling

If the active project's folder no longer exists or is on an unmounted volume,
Ledge **does not recreate it**. It falls back to the watched folder for that
file, surfaces the reason in the shelf, and clears the active project. Silently
recreating a deleted project folder would scatter files into a directory the
user deliberately removed; silently continuing to target an unmounted volume
would fail every download until noticed.

### 13.6 Settings

The General pane gains a Projects section: add, rename, and remove projects.
Removing a project that is currently active resets the destination to Downloads.

## 14. Deferred to v2

- Content- and metadata-based rules (EXIF, resolution, PDF text).
- Per-folder and per-project rule sets (v1 uses one global rule set).
- Rule import/export and sharing.
- Recursive watching of subdirectories.
- Localizations beyond English and Turkish.
- **Bookmark-based file tracking.** When the user moves a filed file elsewhere
  themselves, its shelf row goes stale: it dims, drag is disabled, and undo
  reports the file is no longer at its recorded path. Tracking the file by
  `URL.bookmarkData()` would follow it across moves and renames on the same
  volume, keeping the row live. Deferred because project mode addresses the
  reason files get moved out of `~/Downloads` in the first place — if downloads
  land in the project to begin with, there is no later move to track.
  Reconsider if stale rows prove common in real use.
