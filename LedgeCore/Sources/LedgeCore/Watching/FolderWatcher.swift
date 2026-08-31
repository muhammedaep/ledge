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
/// are opened for it.
///
/// `watches`, `snapshots` and the internal `_unavailableFolders` are the
/// watcher's mutable state. They are confined to `queue`: `start()`/`stop()`
/// hop onto it with `queue.sync`, and every other mutator (the per-folder
/// DispatchSource handlers, and the reconnect timer) already runs on it because
/// it was created with `queue:` as its target.
public final class FolderWatcher: @unchecked Sendable {
    private struct Watch {
        let descriptor: Int32
        let source: DispatchSourceFileSystemObject
    }

    private let folders: [URL]
    private let onNewEntries: @Sendable (Set<URL>) -> Void
    private let reconnectPollInterval: DispatchTimeInterval
    private let emptinessSettleDelay: DispatchTimeInterval
    private let queue = DispatchQueue(label: "com.ledge.folder-watcher")

    // Confined to `queue` — see the type doc above.
    private var watches: [URL: Watch] = [:]
    private var snapshots: [URL: DirectorySnapshot] = [:]
    private var _unavailableFolders: [URL] = []
    private var reconnectTimer: DispatchSourceTimer?

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
            emptinessSettleDelay: .milliseconds(200)
        )
    }

    /// `reconnectPollInterval` controls how often a missing folder is checked
    /// for reappearance, and `emptinessSettleDelay` how long an abrupt
    /// "everything is gone" reading is held before being trusted (see
    /// `rescan`). Both exist only so tests can make these cadences fast
    /// without depending on production timing; the public initializer above
    /// always uses the production defaults.
    init(
        folders: [URL],
        onNewEntries: @escaping @Sendable (Set<URL>) -> Void,
        reconnectPollInterval: DispatchTimeInterval,
        emptinessSettleDelay: DispatchTimeInterval
    ) {
        self.folders = folders
        self.onNewEntries = onNewEntries
        self.reconnectPollInterval = reconnectPollInterval
        self.emptinessSettleDelay = emptinessSettleDelay
    }

    public func start() {
        queue.sync {
            stopLocked()
            for folder in folders {
                attachLocked(folder)
            }
            startReconnectTimerLocked()
        }
    }

    public func stop() {
        queue.sync {
            stopLocked()
        }
    }

    // MARK: - queue-confined

    /// Opens a fresh descriptor and DispatchSource for `folder`. Used both for
    /// the initial watch and to reconnect a folder that went missing and came
    /// back.
    ///
    /// On a fresh watch, the current contents become the baseline with no
    /// diffing (nothing already there counts as new). On a reconnect, the
    /// pre-disappearance snapshot is still in `snapshots` and is left alone
    /// here; `rescan` runs immediately afterwards to diff against it, so
    /// anything already present survives and anything genuinely added while
    /// the folder was gone is still reported.
    private func attachLocked(_ folder: URL) {
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            if !_unavailableFolders.contains(folder) {
                _unavailableFolders.append(folder)
            }
            return
        }

        let isReconnect = snapshots[folder] != nil
        if !isReconnect {
            snapshots[folder] = DirectorySnapshot(scanning: folder)
        }
        _unavailableFolders.removeAll { $0 == folder }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete, .revoke],
            queue: queue
        )
        source.setEventHandler { [weak self] in self?.rescan(folder) }
        source.setCancelHandler { close(descriptor) }
        source.resume()

        watches[folder] = Watch(descriptor: descriptor, source: source)

        if isReconnect {
            rescan(folder)
        }
    }

    private func stopLocked() {
        watches.values.forEach { $0.source.cancel() }
        watches.removeAll()
        snapshots.removeAll()
        _unavailableFolders.removeAll()
        reconnectTimer?.cancel()
        reconnectTimer = nil
    }

    private func startReconnectTimerLocked() {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + reconnectPollInterval, repeating: reconnectPollInterval)
        timer.setEventHandler { [weak self] in self?.reconnectMissingFolders() }
        timer.resume()
        reconnectTimer = timer
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
            queue.asyncAfter(deadline: .now() + emptinessSettleDelay) { [weak self] in
                self?.confirmEmptiness(of: folder)
            }
            return
        }

        commitLocked(current, previous: previous, for: folder)
    }

    /// Re-checked outcome of an abrupt non-empty-to-empty transition: either
    /// the folder is confirmed gone by now (preserve the baseline, flag
    /// unavailable) or it genuinely is just empty (commit that).
    private func confirmEmptiness(of folder: URL) {
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
        onNewEntries(new)
    }

    private func markMissingLocked(_ folder: URL) {
        if let watch = watches.removeValue(forKey: folder) {
            watch.source.cancel()
        }
        if !_unavailableFolders.contains(folder) {
            _unavailableFolders.append(folder)
        }
    }
}
