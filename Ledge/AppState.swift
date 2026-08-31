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

    private let rulesStore = RulesStore.applicationSupport()
    private let projectStore = ProjectStore.applicationSupport()
    private let filing = FilingJournal()
    private let settler = DownloadSettler()
    private var watcher: FolderWatcher?

    init() {
        rules = rulesStore.load()
        projects = projectStore.load()
        Task { await refreshRecords() }
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
        Task.detached(priority: .utility) { watcher.start() }
    }

    func stopWatching() {
        guard let watcher else { return }
        self.watcher = nil
        // `stop()` takes the same queue as `start()`, so it inherits the same
        // block behind a pending attach.
        Task.detached(priority: .utility) { watcher.stop() }
    }

    // MARK: - Rules and projects

    func updateRules(_ newRules: RuleSet) {
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

    /// Files a batch of already-planned moves (Organize Now). Returns the batch id.
    @discardableResult
    func apply(_ plan: [PlannedMove], root: URL) async -> UUID {
        let batch = UUID()
        for planned in plan {
            do {
                let final = try await moveOffMainActor(planned.source, into: planned.destination.folder)
                try await filing.append(MoveRecord(
                    originalName: planned.source.lastPathComponent,
                    from: root,
                    to: final,
                    batchID: batch
                ))
            } catch {
                lastError = String(localized: "Couldn't move \(planned.source.lastPathComponent).")
            }
        }
        await refreshRecords()
        return batch
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

    func undoBatch(_ batchID: UUID) async {
        do {
            try await filing.undoBatch(batchID)
            await refreshRecords()
        } catch {
            lastError = String(localized: "Couldn't undo that batch.")
        }
    }

    private func refreshRecords() async {
        let all = await filing.records
        recentRecords = Array(all.prefix(preferences.shelfSize))
    }
}
