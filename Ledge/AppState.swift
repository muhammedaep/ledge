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
    private(set) var lastError: String?

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
    /// for a 20,000-entry Downloads folder — and blocks for the mount timeout on
    /// an unmounted volume. Read from a view body, that is the same hazard the
    /// shelf's row sweep was moved off the main actor to avoid.
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

    /// False only when a watched folder is *blocked*, never merely absent.
    ///
    /// Unknown counts as fine. Until the first sweep lands, `folderStatus` is
    /// empty and the shelf shows normally — briefly optimistic, the same trade
    /// the row sweep makes, and the right way round: a wrong "everything is
    /// fine" corrects itself a moment later, while a wrong "you are locked out"
    /// is what the user would be staring at.
    var hasFolderAccess: Bool { unreadableFolders.isEmpty }

    /// Whether anything at all can still be filed.
    ///
    /// Not the same question as `hasFolderAccess`, and the difference decides
    /// how much of the shelf is replaced. One blocked folder out of two means
    /// filing still works from the other, so the list, its history and its undo
    /// buttons are live and must stay on screen; only a banner is owed. The
    /// full-screen explanation is for the case it was written for — nothing
    /// coming in from anywhere.
    ///
    /// Unknown counts as usable, for the same reason as above.
    var hasUsableFolder: Bool {
        preferences.watchedFolders.isEmpty
            || preferences.watchedFolders.contains { folderStatus[$0] == .readable || folderStatus[$0] == nil }
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

    /// Commits a rule set, refusing one that would file downloads somewhere the
    /// user did not choose.
    ///
    /// The rules pane disables Save on the same condition, so today this guard
    /// never fires. It is here because the gate has to live at the boundary and
    /// not only on the button: a category name is appended to a URL as one path
    /// component, and an empty one files every match back into the folder it
    /// came from while `..` files into the parent — silently, in the background,
    /// on every download from then on. A second caller added later inherits a
    /// disabled button not at all.
    ///
    /// `RuleSet.canBeSaved` is the same rule the pane reads, from LedgeCore,
    /// where it is tested. Only names block; a duplicate or a shadowed
    /// extension is a state a user can legitimately mean.
    func updateRules(_ newRules: RuleSet) {
        guard newRules.canBeSaved else {
            lastError = String(localized: "Those rules weren't saved — every category needs a folder name.")
            return
        }
        rules = newRules
        try? rulesStore.save(newRules)
    }

    var activeProject: Project? {
        guard let id = preferences.activeProjectID else { return nil }
        return projects.first { $0.id == id }
    }

    func setActiveProject(_ project: Project?) {
        preferences.activeProjectID = project?.id
    }

    func updateProjects(_ newProjects: [Project]) {
        projects = newProjects
        try? projectStore.save(newProjects)
        if let id = preferences.activeProjectID, !newProjects.contains(where: { $0.id == id }) {
            preferences.activeProjectID = nil   // the active project was removed
        }
    }

    /// Where a file found in `foundIn` should be filed. Falls back to the
    /// watched folder when no project is active, or when the active project's
    /// folder has gone (deleted, or on an unmounted volume) — Ledge never
    /// recreates it.
    private func filingRoot(for foundIn: URL) -> URL {
        guard let project = activeProject else { return foundIn }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: project.folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            preferences.activeProjectID = nil
            lastError = String(
                localized: "Project folder is missing — filing into \(foundIn.lastPathComponent) instead.")
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
    func apply(_ plan: [PlannedMove], root: URL) async {
        guard !isOrganizing else { return }
        isOrganizing = true
        defer { isOrganizing = false }

        let batch = UUID()
        var moved = 0
        for planned in plan {
            do {
                let final = try await moveOffMainActor(planned.source, into: planned.destination.folder)
                try await filing.append(MoveRecord(
                    originalName: planned.source.lastPathComponent,
                    from: root,
                    to: final,
                    batchID: batch
                ))
                moved += 1
            } catch {
                lastError = String(localized: "Couldn't move \(planned.source.lastPathComponent).")
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
            guard !rules.destinationFolderNames.contains(url.lastPathComponent) else { continue }
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
                lastError = String(localized: "Couldn't file \(url.lastPathComponent).")
            }
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
            lastError = String(localized: "Couldn't undo \(record.originalName).")
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
            lastError = String(localized: "Couldn't undo that batch.")
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
        lastError = nil
    }
}
