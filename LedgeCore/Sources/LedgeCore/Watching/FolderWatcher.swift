import Foundation

/// Watches folders at depth 1 and reports entries that appeared after start().
///
/// One DispatchSource per folder fires whenever the directory's contents change;
/// the actual "what is new" decision is DirectorySnapshot's, which is unit-tested
/// separately.
///
/// A folder's DispatchSource is bound to the file descriptor opened when the
/// watch is established, not to the path. If the folder is deleted (or its
/// volume unmounts), that descriptor is permanently dead: a folder recreated at
/// the same path afterwards is a different vnode, and no further events ever
/// arrive on the old source. So a folder that goes missing is unwatched and
/// polled for reappearance; when it comes back, a fresh descriptor and source
/// are opened for it. The poll only runs while at least one folder is actually
/// missing — see `ensureReconnectTimerLocked`/`stopReconnectTimerLockedIfIdle`.
///
/// `watches`, `snapshots`, the internal `_unavailableFolders`, `reconnectTimer`
/// and the descriptor-accounting counters are the watcher's mutable state. They
/// are confined to `queue`: `start()`/`stop()` hop onto it with `queue.sync`,
/// and every other mutator (the per-folder DispatchSource handlers, and the
/// reconnect timer) already runs on it because it was created with `queue:` as
/// its target.
///
/// `onNewEntries` is delivered on `deliveryQueue`, a dedicated serial queue
/// that is neither `queue` nor the global concurrent pool (see
/// `commitLocked`): off `queue` so a caller's callback is never re-entrant
/// with respect to this watcher's own internal state — a callback that turns
/// around and calls `stop()` or reads `unavailableFolders` must not deadlock
/// against the very call that is invoking it — and serial rather than
/// concurrent so deliveries stay FIFO-ordered with no two callbacks
/// overlapping and no thread-pool growth under a burst. Moving delivery off
/// `queue` also opened a lifecycle hole on its own: a delivery already
/// scheduled when `stop()` is called could otherwise still land afterwards —
/// mid-restart, or after teardown. `generation` closes that hole: it is
/// bumped every time `stopLocked` runs (both `start()` and `stop()` go
/// through it), captured when a delivery is scheduled, and re-checked when
/// that delivery actually runs; a delivery whose generation has since moved
/// on is dropped instead of delivered.
public final class FolderWatcher: @unchecked Sendable {
    private struct Watch {
        let descriptor: Int32
        let source: DispatchSourceFileSystemObject
    }

    private let folders: [URL]
    private let onNewEntries: @Sendable (Set<URL>) -> Void
    private let reconnectPollInterval: DispatchTimeInterval
    private let reconnectLeeway: DispatchTimeInterval
    private let emptinessSettleDelay: DispatchTimeInterval
    private let queue = DispatchQueue(label: "studio.muhammed.ledge.folder-watcher")
    private let deliveryQueue = DispatchQueue(label: "studio.muhammed.ledge.folder-watcher.delivery")

    // Confined to `queue` — see the type doc above.
    private var watches: [URL: Watch] = [:]
    private var snapshots: [URL: DirectorySnapshot] = [:]
    private var _unavailableFolders: [URL] = []
    private var reconnectTimer: DispatchSourceTimer?
    private var _descriptorsOpened = 0
    private var _descriptorsClosed = 0
    private var generation = 0
    private var pendingSettleCount = 0

    /// Folders currently unwatched because they don't exist (never existed, were
    /// deleted, or their volume unmounted). Safe to read from any thread.
    public var unavailableFolders: [URL] {
        queue.sync { _unavailableFolders }
    }

    public convenience init(
        folders: [URL], onNewEntries: @escaping @Sendable (Set<URL>) -> Void
    ) {
        self.init(
            folders: folders,
            onNewEntries: onNewEntries,
            reconnectPollInterval: .milliseconds(500),
            emptinessSettleDelay: .milliseconds(200),
            reconnectLeeway: .seconds(5)
        )
    }

    /// `reconnectPollInterval` controls how often a missing folder is checked
    /// for reappearance, and `emptinessSettleDelay` how long an abrupt
    /// "everything is gone" reading is held before being trusted (see
    /// `rescan`). `reconnectLeeway` gives Dispatch slack on the *first*
    /// deadline of the repeating reconnect timer only — measured directly: a
    /// 500ms-repeating timer with 5s of leeway still fires every 500ms, since
    /// Dispatch clamps leeway on a repeating timer to its initial fire and
    /// applies none to the recurring ones after that. It is not a meaningful
    /// battery lever on its own; the actual battery win is entirely
    /// `ensureReconnectTimerLocked`/`stopReconnectTimerLockedIfIdle` gating
    /// the timer to run only while a folder is actually missing, which is
    /// the rare, transient case rather than the steady state. All three
    /// parameters exist so tests can make these cadences fast without
    /// depending on production timing; the public initializer above always
    /// uses the production defaults, keeping `reconnectPollInterval` at
    /// 500ms rather than raising it further — the timer already costs
    /// nothing while everything is fine, and 500ms keeps reconnection
    /// prompt for the case that matters: a user who just reconnected a
    /// drive and expects Ledge to notice quickly, not after several
    /// seconds.
    init(
        folders: [URL],
        onNewEntries: @escaping @Sendable (Set<URL>) -> Void,
        reconnectPollInterval: DispatchTimeInterval,
        emptinessSettleDelay: DispatchTimeInterval,
        reconnectLeeway: DispatchTimeInterval
    ) {
        self.folders = folders
        self.onNewEntries = onNewEntries
        self.reconnectPollInterval = reconnectPollInterval
        self.emptinessSettleDelay = emptinessSettleDelay
        self.reconnectLeeway = reconnectLeeway
    }

    public func start() {
        queue.sync {
            stopLocked()
            for folder in folders {
                attachLocked(folder)
            }
        }
    }

    public func stop() {
        queue.sync {
            stopLocked()
        }
    }

    /// Cancels every open watch and the reconnect timer without waiting for
    /// `queue` — safe to call from `deinit`, which may run on any thread and
    /// must not risk a `queue.sync` deadlock. `DispatchSourceFileSystemObject.
    /// cancel()` is documented as safe to call from any thread; the actual
    /// cancel handlers (which close the descriptors) run later, on `queue`,
    /// once nothing else references this instance.
    deinit {
        watches.values.forEach { $0.source.cancel() }
        reconnectTimer?.cancel()
    }

    // MARK: - queue-confined

    /// Opens a fresh descriptor and DispatchSource for `folder`. Used both for
    /// the initial watch and to reconnect a folder that went missing and came
    /// back. A no-op if `folder` is already watched, so a duplicate entry in
    /// `folders` (or an overlapping reconnect attempt) never opens a second
    /// descriptor that would silently replace and leak the first.
    ///
    /// On a fresh watch, the current contents become the baseline with no
    /// diffing (nothing already there counts as new). On a reconnect, the
    /// pre-disappearance snapshot is still in `snapshots` and is left alone
    /// here; `rescan` runs immediately afterwards to diff against it, so
    /// anything already present survives and anything genuinely added while
    /// the folder was gone is still reported.
    private func attachLocked(_ folder: URL) {
        guard watches[folder] == nil else { return }

        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            markMissingLocked(folder)
            return
        }
        _descriptorsOpened += 1

        let isReconnect = snapshots[folder] != nil
        if !isReconnect {
            snapshots[folder] = DirectorySnapshot(scanning: folder)
        }
        _unavailableFolders.removeAll { $0 == folder }
        stopReconnectTimerLockedIfIdle()

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.rescan(folder) }
        source.setCancelHandler { [weak self] in
            close(descriptor)
            self?._descriptorsClosed += 1
        }
        source.resume()

        watches[folder] = Watch(descriptor: descriptor, source: source)

        if isReconnect {
            rescan(folder)
        }
    }

    private func stopLocked() {
        // Bumped here, not separately in start()/stop(), because both always
        // go through this: start() calls it to reset before reattaching,
        // stop() calls it directly. Any delivery scheduled against the
        // generation that existed before this call is now stale.
        generation += 1
        watches.values.forEach { $0.source.cancel() }
        watches.removeAll()
        snapshots.removeAll()
        _unavailableFolders.removeAll()
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    /// Starts the reconnect poll if it isn't already running. Only called
    /// while at least one folder is unavailable — an idle watcher (nothing
    /// missing) has no timer at all, so it costs nothing while everything is
    /// fine, which is the normal case for the lifetime of a menu bar app.
    private func ensureReconnectTimerLocked() {
        guard reconnectTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + reconnectPollInterval,
            repeating: reconnectPollInterval,
            leeway: reconnectLeeway
        )
        timer.setEventHandler { [weak self] in self?.reconnectMissingFolders() }
        timer.resume()
        reconnectTimer = timer
    }

    /// Stops the reconnect poll once nothing is left to reconnect.
    private func stopReconnectTimerLockedIfIdle() {
        guard _unavailableFolders.isEmpty else { return }
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    private func reconnectMissingFolders() {
        for folder in _unavailableFolders where watches[folder] == nil {
            guard FileManager.default.fileExists(atPath: folder.path) else { continue }
            attachLocked(folder)
        }
    }

    /// A12: an unavailable folder must not be read as "everything was
    /// deleted". DirectorySnapshot(scanning:) returns an empty snapshot for a
    /// folder that is gone; storing that as the new baseline would make every
    /// file look new the moment the folder comes back (a remounted external
    /// drive, in particular). So the snapshot is only ever replaced while the
    /// folder still exists — a folder that is gone keeps its last known-good
    /// snapshot untouched and is flagged unavailable instead.
    ///
    /// This existence check is not redundant with the settle-delay check
    /// below even though every test that deletes a *non-empty* folder never
    /// reaches it (their existence check happens inside `confirmEmptiness`
    /// instead): a folder that is already empty when it is deleted produces
    /// `current.entries.isEmpty == previous.entries.isEmpty == true`, which
    /// never enters the settle branch at all. Without this check that
    /// deletion would go completely unnoticed — not merely mis-attributed,
    /// but silently never flagged unavailable and never reconnected.
    ///
    /// A folder that genuinely had all its contents deleted while still
    /// existing is unaffected by this guard: it still updates the snapshot to
    /// empty and still emits nothing, because `newEntries` only reports
    /// additions.
    ///
    /// One more wrinkle, found by actually running this against real
    /// deletions rather than trusting the reasoning above: removing a
    /// non-empty directory (`FileManager.removeItem`, and presumably a real
    /// unmount too) is not atomic. It unlinks the contents first — which
    /// fires a plain "write" event while the folder still, briefly, exists
    /// and is empty — and only afterwards removes the directory itself. Taken
    /// at face value, that transient "still exists, but empty" reading is
    /// indistinguishable from someone genuinely emptying the folder, and the
    /// existence guard above lets it through, wiping the true baseline a
    /// moment before the real disappearance is even detected. So an abrupt
    /// non-empty-to-empty transition is not trusted immediately; it is
    /// re-checked after `emptinessSettleDelay`, exactly the way
    /// DownloadSettler waits out a transient reading rather than trusting a
    /// single sample.
    private func rescan(_ folder: URL) {
        guard FileManager.default.fileExists(atPath: folder.path) else {
            markMissingLocked(folder)
            return
        }

        let current = DirectorySnapshot(scanning: folder)
        let previous = snapshots[folder] ?? DirectorySnapshot(entries: [])

        if current.entries.isEmpty, !previous.entries.isEmpty {
            // Generation-guarded for the same reason a scheduled delivery is
            // (see commitLocked): this closure runs later, on `queue`, after
            // an arbitrary delay. If stop() runs in the meantime, it must
            // not resurrect anything — but unlike a delivery, what
            // confirmEmptiness does when unguarded is far worse than
            // re-emitting one stale event: finding this folder "confirmed
            // gone" calls markMissingLocked, which calls
            // ensureReconnectTimerLocked, re-arming the reconnect poll on a
            // watcher that stop() already tore down. That poll then keeps
            // running indefinitely, can reopen a descriptor, and can emit
            // again — unbounded in time, not a one-shot stale event.
            let settleGeneration = generation
            pendingSettleCount += 1
            queue.asyncAfter(deadline: .now() + emptinessSettleDelay) { [weak self] in
                self?.confirmEmptiness(of: folder, generation: settleGeneration)
            }
            return
        }

        commitLocked(current, previous: previous, for: folder)
    }

    /// Re-checked outcome of an abrupt non-empty-to-empty transition: either
    /// the folder is confirmed gone by now (preserve the baseline, flag
    /// unavailable) or it genuinely is just empty (commit that). Dropped
    /// entirely if `stop()`/`start()` has run since this was scheduled — see
    /// `rescan`.
    private func confirmEmptiness(of folder: URL, generation settleGeneration: Int) {
        pendingSettleCount -= 1
        // Runs on `queue` already (scheduled via queue.asyncAfter), so
        // reading `generation` directly — no cross-queue hop needed here,
        // unlike the delivery closure's check.
        guard generation == settleGeneration else { return }

        guard FileManager.default.fileExists(atPath: folder.path) else {
            markMissingLocked(folder)
            return
        }

        let current = DirectorySnapshot(scanning: folder)
        let previous = snapshots[folder] ?? DirectorySnapshot(entries: [])
        commitLocked(current, previous: previous, for: folder)
    }

    private func commitLocked(_ current: DirectorySnapshot, previous: DirectorySnapshot, for folder: URL) {
        snapshots[folder] = current

        let new = current.newEntries(comparedTo: previous)
        guard !new.isEmpty else { return }

        // Dispatched to deliveryQueue, not called inline and not on
        // DispatchQueue.global(): `onNewEntries` is the caller's code, and
        // this call happens while `queue` is doing its own bookkeeping. A
        // callback that calls back into this watcher (stop(), reading
        // unavailableFolders) would deadlock if it ran here — sync on the
        // very queue it is already running on always deadlocks. A dedicated
        // serial queue keeps that fix while adding FIFO ordering and no
        // thread-pool growth under a burst, for free.
        //
        // The generation check below is a separate fix: moving delivery off
        // `queue` made it possible for a delivery scheduled just before
        // stop() to still land afterwards — mid-restart, or after teardown —
        // filing a stale arrival against whatever folder happens to be
        // current by then. Capturing `generation` now and re-checking it
        // when the delivery actually runs drops anything scheduled against a
        // generation that has since moved on.
        let deliveryGeneration = generation
        let callback = onNewEntries
        deliveryQueue.async { [weak self] in
            guard let self else { return }
            guard self.queue.sync(execute: { self.generation }) == deliveryGeneration else { return }
            // Note: this check only stops a delivery that hasn't started yet.
            // A callback already past this guard (already running) is not
            // interrupted by a concurrent stop() — it runs to completion.
            // That's intentional, not a defect: the generation check's job
            // is to drop stale, not-yet-started work, not to cancel a
            // callback already in flight.
            callback(new)
        }
    }

    private func markMissingLocked(_ folder: URL) {
        if let watch = watches.removeValue(forKey: folder) {
            watch.source.cancel()
        }
        if !_unavailableFolders.contains(folder) {
            _unavailableFolders.append(folder)
        }
        ensureReconnectTimerLocked()
    }

    // MARK: - test-only introspection (internal, not part of the public API)

    /// The raw descriptor currently open for `folder`, if any.
    func descriptorForTesting(_ folder: URL) -> Int32? {
        queue.sync { watches[folder]?.descriptor }
    }

    /// Every descriptor this instance has opened, less every one it has
    /// closed. Should settle at zero once nothing is left watching.
    var descriptorLeakBalanceForTesting: Int {
        queue.sync { _descriptorsOpened - _descriptorsClosed }
    }

    /// Whether the reconnect poll is currently running.
    var isReconnectTimerRunningForTesting: Bool {
        queue.sync { reconnectTimer != nil }
    }

    /// Whether an emptiness-settle check (see `rescan`/`confirmEmptiness`) is
    /// currently scheduled and hasn't run yet. Lets a test synchronize on
    /// "the settle check has actually been scheduled" or "it has actually
    /// fired" instead of guessing how long that takes under real filesystem
    /// events and (for the latter) real dispatch timing, both of which are
    /// unreliable to estimate under this file's parallel test execution.
    var hasPendingEmptinessSettleForTesting: Bool {
        queue.sync { pendingSettleCount > 0 }
    }
}
