import Foundation
import Observation
import LedgeCore

/// Owns the move journal and every operation that writes to it.
///
/// `FileMover` serializes its "pick a free name, then move onto it" critical
/// section behind a process-wide lock, and that section spans the move itself —
/// for a large file across volumes, a full copy. So no move may run on the main
/// actor, or a bulk pass would freeze the menu bar.
///
/// Undo is the awkward case. `UndoService` couples the move and the journal
/// write into one synchronous call, so the move cannot be lifted out of it
/// without reimplementing the service's rules (its existence check, its
/// remove-after-restore ordering, its skip-and-keep batch behaviour) in this
/// target, where nothing tests them. Putting the journal on an actor solves it
/// from the other side: `UndoService` runs whole, off the main actor, and
/// `MoveJournal` — a plain non-Sendable class with a mutable array inside —
/// stays confined to one isolation domain instead of being raced between a
/// detached undo and a `journal.append` from the watcher.
private actor FilingJournal {
    private let journal = MoveJournal.applicationSupport()

    /// Newest first, and the full journal — the shelf decides how much of it to show.
    var records: [MoveRecord] { journal.records }

    func append(_ record: MoveRecord) throws {
        try journal.append(record)
    }

    func undo(_ record: MoveRecord) throws {
        try UndoService(mover: FileMover(), journal: journal).undo(record)
    }

    func undoBatch(_ batchID: UUID) throws {
        try UndoService(mover: FileMover(), journal: journal).undoBatch(batchID)
    }
}

/// Wires the watcher, settler, categorizer, mover and journal into one live
/// pipeline, and holds the state the menu bar renders.
@MainActor
@Observable
final class AppState {
    let preferences = Preferences()
    private(set) var rules: RuleSet
    private(set) var projects: [Project] = []
    private(set) var recentRecords: [MoveRecord] = []
    /// What went wrong, and whether the user can do anything about it here.
    ///
    /// A plain `String?` could not answer the second question, so a permission
    /// failure read exactly like a full disk: a dead end. Stored as one value
    /// rather than two properties so the message and its affordance cannot
    /// drift — every site that sets one sets the other, and the compiler says
    /// so, because `lastError` below is get-only.
    struct Notice: Equatable {
        var message: String
        var offersPrivacySettings = false
    }

    private(set) var notice: Notice?

    var lastError: String? { notice?.message }
    var lastErrorOffersPrivacySettings: Bool { notice?.offersPrivacySettings ?? false }

    /// True while an Organize Now batch is being applied or undone.
    ///
    /// Here rather than in the sheet because what it guards is a filesystem
    /// operation, not a view. As `@State` it was destroyed with the sheet: the
    /// user could dismiss mid-batch — Cancel never disabled — and reopen onto a
    /// fresh `false`, starting a second pass over a folder the first was still
    /// moving through. The batch outlives the window that started it, so the
    /// flag has to as well.
    private(set) var isOrganizing = false

    /// The most recent Organize Now batch and how it went, kept for the same
    /// reason: dismissing the sheet mid-batch used to lose the only handle on a
    /// batch that was still running, and with it the ability to undo it.
    private(set) var lastOrganizeOutcome: BatchOutcome?

    private let rulesStore = RulesStore.applicationSupport()
    private let projectStore = ProjectStore.applicationSupport()
    private let filing = FilingJournal()
    private let settler = DownloadSettler()
    private var watcher: FolderWatcher?

    /// Carries watcher lifecycle work off the main actor, in submission order.
    /// Serial, not `DispatchQueue.global()`: the ordering is the whole point
    /// (see `stopWatching()`), and the global queue is concurrent — it dequeues
    /// in FIFO order but makes no promise about which block reaches the
    /// watcher's own queue first.
    private let watcherQueue = DispatchQueue(label: "com.ledge.watcher-lifecycle", qos: .utility)

    init() {
        rules = rulesStore.load()
        // Spec §9: the user is told once. `RulesStore` reports the fact and
        // stops there — it has no string catalog, so the sentence has to be
        // composed here — and until now nobody read it, so a hand-edited
        // rules.json was quarantined and replaced by the defaults with nothing
        // whatsoever on screen. The core produced the data and the app produced
        // no sentence.
        //
        // The two cases are different news and must not share a wording. A
        // corrupt file was moved aside, so the user's edits are recoverable and
        // the message has to say where they went; a repaired one was read and
        // most of it survived, with nothing to recover.
        if rulesStore.lastLoadWasCorrupt {
            notice = Notice(message: String(localized: "Your rules file couldn't be read, so Ledge went back to the defaults. The old file was renamed, not deleted."))
        } else if rulesStore.lastLoadWasRepaired {
            notice = Notice(message: String(localized: "Some of your rules named a folder Ledge can't use and were removed. The rest are unchanged."))
        }

        // One-time edits Ledge makes to a rule set it did not write. Saved only
        // when something actually changed, so a rule set already carrying every
        // marker is never rewritten — and a save that fails leaves the marker
        // unrecorded, which means the migration is offered again rather than
        // silently lost.
        //
        // `rules` above is already `RulesStore.load()`'s return, which is
        // `sanitized()` — a hand-edited file with an unusable category comes
        // back repaired in memory. Before this migration existed, nothing
        // wrote that back, so a bad file kept the user's own text until they
        // next touched Settings. `save(migrated)` below persists whatever is
        // in memory, so the repair now reaches disk too, as a side effect of
        // saving at all — not something this migration set out to do, and not
        // worth a guard against: there is no unsanitized copy left to save
        // instead, only the raw file this class no longer holds.
        let migrated = rules.migrated()
        if migrated != rules {
            do {
                try rulesStore.save(migrated)
                rules = migrated
            } catch {
                notice = Notice(message: String(localized: "Couldn't save your rules."))
            }
        }
        projects = projectStore.load()
        Task { await refreshRecords() }
        Task { await refreshFolderStatus() }
    }

    // MARK: - Watching

    func startWatching() {
        stopWatching()
        guard preferences.automaticFilingEnabled else { return }

        // Callbacks arrive on the watcher's own serial queue, not the main
        // actor, so the hop back is explicit.
        let watcher = FolderWatcher(folders: preferences.watchedFolders) { [weak self] urls in
            Task { await self?.handle(urls) }
        }
        self.watcher = watcher

        // `start()` blocks its caller until every folder is attached, and
        // attaching opens a descriptor for each one. `~/Downloads` is
        // TCC-protected, and that `open()` does not return until the user
        // answers the consent prompt — measured, not theorised: called on the
        // main thread from `App.init()` it wedges the process in `__open`
        // before the run loop starts, so no menu bar icon ever appears and the
        // app looks dead until access is granted. Off the main actor it stays
        // a background wait. `FolderWatcher` is `Sendable` and serializes
        // itself on its own queue.
        //
        // On `watcherQueue` rather than in a `Task.detached`: a detached task
        // would spend that whole wait sitting in a blocking syscall on a
        // cooperative-pool thread, which the pool sizes for work that never
        // blocks.
        watcherQueue.async { watcher.start() }
    }

    func stopWatching() {
        guard let watcher else { return }
        self.watcher = nil
        // Same queue as the `start()` above, and serial, so a stop submitted
        // after a start cannot overtake it. Two unordered dispatches could:
        // "File downloads automatically" toggled off and straight back on
        // submits `stop()` for the same instance the previous `startWatching()`
        // submitted `start()` for, and `start()` landing second would reattach
        // descriptors on a watcher this class no longer references — live, and
        // unreachable to stop. `stop()` takes the same queue inside the watcher
        // as `start()`, so it still inherits the block behind a pending attach.
        watcherQueue.async { watcher.stop() }
    }

    // MARK: - Watched folders

    /// What each watched folder's last check said. Cached, not computed on
    /// demand: `FolderAccess.of` lists a directory, which is `O(entries)` — 50ms
    /// for a 20,000-entry Downloads folder — and blocks until the mount times out
    /// against a network volume that has stopped answering. Not against a
    /// detached *local* volume, which measures at 0.0023 s; the same correction
    /// the shelf's row sweep carries. Read from a view body, either way, that is
    /// the same hazard the row sweep was moved off the main actor to avoid.
    ///
    /// The cost of caching is staleness, and the answer does change outside this
    /// process: the user grants access in System Settings, or plugs the drive
    /// back in, with no notification to observe. So it is refreshed on every
    /// signal that suggests it may have moved — see `refreshFolderStatus()`.
    private(set) var folderStatus: [URL: FolderAccess] = [:]

    /// Bumped by every `refreshFolderStatus()`; a sweep that finishes after a
    /// later one started publishes nothing.
    private var folderStatusGeneration = 0

    /// Watched folders that exist but cannot be read — a declined or
    /// never-granted TCC prompt. This is the one the user can actually fix by
    /// granting permission.
    var unreadableFolders: [URL] {
        preferences.watchedFolders.filter { folderStatus[$0] == .unreadable }
    }

    /// Watched folders that are not there at all: deleted, or on a volume that
    /// has been ejected. Not a permission problem, and must never be presented
    /// as one — no consent dialog can grant a folder that does not exist.
    var missingFolders: [URL] {
        preferences.watchedFolders.filter { folderStatus[$0] == .missing }
    }

    /// Whether anything at all can still be filed.
    ///
    /// This is the whole-app question, and it is deliberately *not* "is every
    /// folder fine". One blocked folder out of two means filing still works from
    /// the other, so the list, its history and its undo buttons are live and must
    /// stay on screen; only a banner is owed. The full-screen explanation is for
    /// the case it was written for — nothing coming in from anywhere.
    ///
    /// There used to be a `hasFolderAccess` beside this one, false as soon as
    /// *any* watched folder was blocked. It is gone rather than merely unused:
    /// the shelf was moved off it once and the Organize Now button was left
    /// behind on it, which is how one locked folder came to disable the feature
    /// for the readable folder next to it. A predicate whose only remaining use
    /// is to be reached for by mistake is worth deleting.
    var hasUsableFolder: Bool {
        preferences.watchedFolders.isEmpty || preferences.watchedFolders.contains(where: isUsable)
    }

    /// Whether *this* folder can be filed from — the question anything operating
    /// on one folder at a time has to ask, and the one Organize Now asks, since
    /// it works on a single folder chosen in its own picker.
    ///
    /// Unknown counts as usable. Until the first sweep lands `folderStatus` is
    /// empty and everything shows normally — briefly optimistic, the same trade
    /// the shelf's row sweep makes, and the right way round: a wrong "everything
    /// is fine" corrects itself a moment later, while a wrong "you are locked
    /// out" is what the user would be staring at.
    func isUsable(_ folder: URL) -> Bool {
        let status = folderStatus[folder]
        return status == .readable || status == nil
    }

    /// Re-checks every watched folder, off the main actor.
    ///
    /// Called on launch, whenever the watched folders change, and from the shelf
    /// on the same signals that refresh row liveness — the popover opening is
    /// exactly when a stale answer would be seen.
    ///
    /// Those overlap: adding a folder starts a refresh while the shelf's own may
    /// still be running. A plain assignment there is last-writer-wins, and the
    /// older sweep — which never saw the new folder — would erase its entry. So
    /// a superseded sweep publishes nothing, the way `FolderWatcher` drops a
    /// delivery whose generation has moved on.
    func refreshFolderStatus() async {
        folderStatusGeneration += 1
        let generation = folderStatusGeneration
        let folders = preferences.watchedFolders

        let checked = await Task.detached(priority: .userInitiated) {
            var status: [URL: FolderAccess] = [:]
            for folder in folders {
                status[folder] = FolderAccess.of(folder)
            }
            return status
        }.value

        guard generation == folderStatusGeneration else { return }
        // Keyed by identity, not by spelling, so an entry cannot outlive the
        // folder it describes.
        folderStatus = checked.filter { FolderIdentity.contains(preferences.watchedFolders, $0.key) }
    }

    /// Adding a folder that is already watched by another spelling would open a
    /// second `O_EVTONLY` descriptor on the same vnode and report every new file
    /// twice. `FolderIdentity` owns that comparison, shared with projects.
    func addWatchedFolder(_ url: URL) {
        let updated = FolderIdentity.adding(url, to: preferences.watchedFolders)
        guard updated.count != preferences.watchedFolders.count else { return }
        preferences.watchedFolders = updated
        startWatching()
        Task { await refreshFolderStatus() }
    }

    /// Never removes the last one: with no watched folders the app would run
    /// with nothing to do and no visible reason why.
    func removeWatchedFolder(_ url: URL) {
        guard preferences.watchedFolders.count > 1 else { return }
        preferences.watchedFolders = FolderIdentity.removing(url, from: preferences.watchedFolders)
        // Cleared by identity too. Keyed on the caller's spelling, an entry for
        // the same folder written under a different spelling would survive the
        // removal and keep reporting a folder that is no longer watched.
        folderStatus = folderStatus.filter { !FolderIdentity.sameFolder($0.key, url) }
        startWatching()
        Task { await refreshFolderStatus() }
    }

    // MARK: - Rules and projects

    /// Commits a rule set. Returns whether it was written.
    ///
    /// The refusal itself is `RulesStore.save`'s, in LedgeCore. It used to be a
    /// `guard` right here, which addressed the danger but proved nothing:
    /// mutating that guard to a no-op killed no test, because this target has
    /// none by design. A rule in the app target is a rule nobody can test.
    ///
    /// In-memory rules follow the file rather than leading it. A refused or
    /// failed write leaves `rules` exactly as it was, so what Ledge files by
    /// never diverges from what it would load on next launch — and the pane
    /// still holds the user's draft, so nothing they typed is lost.
    @discardableResult
    func updateRules(_ newRules: RuleSet) -> Bool {
        do {
            try rulesStore.save(newRules)
            rules = newRules
            return true
        } catch let unusable as RuleSet.Unusable {
            // Names, not a disk problem — and worth naming, since the whole
            // point is that the user cannot see where the bad one is.
            let names = unusable.names.map { "“\($0)”" }.formatted(.list(type: .and))
            notice = Notice(message: String(localized: "Those rules weren't saved: \(names) can't be a folder name."))
            return false
        } catch {
            notice = Notice(message: String(localized: "Couldn't save your rules."))
            return false
        }
    }

    var activeProject: Project? {
        guard let id = preferences.activeProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    func setActiveProject(_ project: Project?) {
        preferences.activeProjectID = project?.id
    }

    /// Commits a project list. Returns whether it was written.
    ///
    /// Ordered exactly like `updateRules`, and for the reason its comment gives:
    /// in-memory state follows the file rather than leading it. This used to
    /// assign first and then `try?` the write away, so a failed save left the
    /// menu naming projects that would be gone on next launch — and, worse,
    /// could clear `activeProjectID` on the strength of a list that was never
    /// written. Nothing moves unless the write lands.
    @discardableResult
    func updateProjects(_ newProjects: [Project]) -> Bool {
        do {
            try projectStore.save(newProjects)
        } catch {
            notice = Notice(message: String(localized: "Couldn't save your projects."))
            return false
        }
        projects = newProjects
        if let id = preferences.activeProjectID, !newProjects.contains(where: { $0.id == id }) {
            preferences.activeProjectID = nil   // the active project was removed
        }
        return true
    }

    /// Where a file found in `foundIn` should be filed. Falls back to the
    /// watched folder when no project is active, or when the active project's
    /// folder has gone (deleted, or on an unmounted volume) — Ledge never
    /// recreates it.
    private func filingRoot(for foundIn: URL) -> URL {
        guard let project = activeProject else { return foundIn }
        // `isDirectory`, and deliberately NOT `FileEntry.exists`.
        //
        // The rest of this app was moved onto `exists` (lstat) because a
        // dangling symlink is a real entry that `FileMover` can move. Applying
        // that uniformly here looks like tidying and is a regression: a
        // dangling link at the project folder would pass an `exists` guard, and
        // `FileMover.createDirectory` would then fail on it, turning this clean
        // "the project folder is gone, filing into the watched folder instead"
        // fallback into a per-file "Couldn't file …" for every download.
        //
        // The two calls answer different questions on purpose — see
        // `FileEntry`. This one has to follow symlinks: a symlinked project
        // folder is somewhere a download can land, and a dangling one is not,
        // which is exactly the case this guard exists to catch.
        guard FileEntry.isDirectory(atPath: project.folder.path) else {
            preferences.activeProjectID = nil
            notice = Notice(message: String(
                localized: "Project folder is missing — filing into \(foundIn.lastPathComponent) instead."))
            return foundIn
        }
        return project.folder
    }

    // MARK: - Filing

    /// Files a batch of already-planned moves (Organize Now).
    ///
    /// Re-entry is refused rather than queued. Two passes over one folder at
    /// once are not destructive — `FileMover` serializes and never overwrites,
    /// so nothing is lost or duplicated — but the second pass plans sources the
    /// first has already moved, and every one of them comes back as "Couldn't
    /// move …" for a file that is sitting safely where the user asked for it.
    func apply(_ plan: [PlannedMove]) async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }

        let batch = UUID()
        var moved = 0
        for planned in plan {
            do {
                let final = try await moveOffMainActor(planned.source, into: planned.destination.folder)
                // The source's own parent, not the batch root: `from` is where
                // undo puts the file back, and it has to be where the file was.
                try await filing.append(MoveRecord(
                    originalName: planned.source.lastPathComponent,
                    from: planned.source.deletingLastPathComponent(),
                    to: final,
                    batchID: batch
                ))
                moved += 1
            } catch {
                notice = failure(String(localized: "Couldn't move \(planned.source.lastPathComponent)."), error)
            }
        }
        lastOrganizeOutcome = BatchOutcome(id: batch, moved: moved, attempted: plan.count)
        await refreshRecords()
    }

    private func handle(_ urls: Set<URL>) async {
        for url in urls {
            // The destination folders are created by our own moves, so the
            // watcher reports them as new entries the moment the first file is
            // filed. Skipping them is `RuleSet`'s rule, shared with Organize
            // Now; without it `Documents` would itself be filed into `Other/`,
            // taking everything already filed there with it.
            guard !rules.reservesFolderName(url.lastPathComponent) else { continue }
            guard await settler.settle(url) == .ready else { continue }
            guard let facts = FileFacts(url: url) else { continue }

            // `root` is where the file was found, which is what undo puts it
            // back into. Only the filing root changes under a project.
            let root = url.deletingLastPathComponent()
            let destination = Categorizer.destination(
                for: facts, in: filingRoot(for: root), using: rules)

            do {
                let final = try await moveOffMainActor(url, into: destination.folder)
                try await filing.append(MoveRecord(
                    originalName: url.lastPathComponent, from: root, to: final))
                await refreshRecords()
            } catch {
                notice = failure(String(localized: "Couldn't file \(url.lastPathComponent)."), error)
            }
        }
    }

    /// A failure headline with the reason appended, when there is one worth
    /// showing.
    ///
    /// Added after the first real run put "Couldn't file Magister-Overview-EN.pptx."
    /// on screen and nothing else. Every one of these sites had the reason in
    /// hand — `MoveError.underlying` carries the domain, the code and the
    /// system's own description — and threw it away in the `catch`. A user
    /// could not tell a permission problem from a full disk, and neither could
    /// anyone they reported it to.
    ///
    /// The phrasing lives here rather than on `MoveError` because `LedgeCore`
    /// produces data and the app produces sentences — a rule `make strings`
    /// enforces by refusing localization APIs inside the package.
    private func failure(_ headline: String, _ error: Error) -> Notice {
        let reason = reason(for: error)
        return Notice(
            message: reason.map { "\(headline) \($0)" } ?? headline,
            offersPrivacySettings: isPermissionDenied(error))
    }

    /// Whether the route out of this failure is System Settings.
    ///
    /// Offered only for a failure that actually names permission. A full disk
    /// and a vanished folder are dead ends here too, and a button that opens
    /// the wrong panel is worse than no button — it sends the user to change a
    /// setting that was never the problem.
    ///
    /// Not a guarantee that the panel holds the answer. macOS refuses to move a
    /// file that is also hard-linked into a protected directory, and phrases
    /// that refusal as a permission error naming the *destination* — measured
    /// on 2026-09-01, where the destination was demonstrably writable and the
    /// source's second link was inside another app's Application Support. The
    /// button is a route worth offering, not a diagnosis.
    private func isPermissionDenied(_ error: Error) -> Bool {
        switch error as? MoveError {
        case .destinationNotWritable:
            return true
        case let .underlying(domain, code, _):
            switch domain {
            case NSCocoaErrorDomain:
                return code == NSFileWriteNoPermissionError
                    || code == NSFileReadNoPermissionError
            case NSPOSIXErrorDomain:
                return code == Int(EPERM) || code == Int(EACCES)
            default:
                return false
            }
        default:
            return false
        }
    }

    private func reason(for error: Error) -> String? {
        switch error as? MoveError {
        case .sourceMissing:
            return String(localized: "It is no longer where Ledge found it.")
        case let .destinationNotWritable(folder):
            return String(localized: "Ledge can't write to \(folder.lastPathComponent).")
        case let .underlying(_, _, description):
            // Already localized by the system, and more specific than anything
            // written here could be.
            return description
        case nil:
            let described = (error as NSError).localizedDescription
            return described.isEmpty ? nil : described
        }
    }

    /// `FileMover` serializes process-wide and its critical section spans the
    /// move itself, so it must never be called on the main actor.
    private nonisolated func moveOffMainActor(_ source: URL, into folder: URL) async throws -> URL {
        try await Task.detached(priority: .utility) {
            try FileMover().move(source, into: folder)
        }.value
    }

    // MARK: - Undo

    func undo(_ record: MoveRecord) async {
        do {
            try await filing.undo(record)
            await refreshRecords()
        } catch {
            notice = failure(String(localized: "Couldn't undo \(record.originalName)."), error)
        }
    }

    /// Whether ⌘Z has anything to act on.
    ///
    /// Drives `.disabled` rather than an early return with an error. An empty
    /// shelf is not a failure the user needs told about — measured on the
    /// panel, a disabled shortcut makes `performKeyEquivalent` answer false, so
    /// the keystroke is simply not consumed.
    var canUndo: Bool { UndoTarget.mostRecent(in: recentRecords) != .nothing }

    /// ⌘Z. Spec §7.5: undoes the most recent record, or the whole batch it
    /// belongs to.
    ///
    /// *Which* of those it is, is `UndoTarget`'s decision, in LedgeCore with
    /// tests — it turns on `batchID`, and a rule that picks between two
    /// different filesystem operations does not belong in a keyboard handler.
    /// This method only dispatches, so both paths keep the existing guards and
    /// the existing `lastError` reporting: a file gone from its recorded path
    /// still surfaces "Couldn't undo …" rather than failing silently.
    func undoMostRecent() async {
        switch UndoTarget.mostRecent(in: recentRecords) {
        case .nothing:
            break
        case .record(let record):
            await undo(record)
        case .batch(let batchID):
            await undoBatch(batchID)
        }
    }

    /// Puts a whole Organize Now batch back. Takes the same guard as `apply`:
    /// undo moves files too, and a pass starting while one is running would
    /// plan against a folder in the middle of being emptied.
    func undoBatch(_ batchID: UUID) async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }

        do {
            try await filing.undoBatch(batchID)
            // The batch is gone; there is nothing left to offer an undo for.
            if lastOrganizeOutcome?.id == batchID { lastOrganizeOutcome = nil }
            await refreshRecords()
        } catch {
            notice = failure(String(localized: "Couldn't undo that batch."), error)
        }
    }

    /// Re-reads the journal into `recentRecords`. Settings calls it when the
    /// shelf size changes: the trim to `shelfSize` happens at read time, so
    /// nothing else would apply a new size until the next file was filed.
    func reloadShelf() async {
        await refreshRecords()
    }

    private func refreshRecords() async {
        let all = await filing.records
        recentRecords = Array(all.prefix(preferences.shelfSize))
    }

    // MARK: - Errors

    /// Dismisses the last failure. `lastError` is otherwise write-only from
    /// outside this class, and the shelf needs to be able to put the banner
    /// away once the user has read it.
    func clearError() {
        notice = nil
    }
}
