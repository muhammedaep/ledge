import Testing
import Foundation
@testable import LedgeCore

@Test func watcherReportsAFileCreatedAfterItStarted() async throws {
    let temp = try TempDirectory()
    try temp.writeFile("pre-existing.png")

    let box = Box()
    let watcher = FolderWatcher(folders: [temp.url]) { urls in box.add(urls) }
    watcher.start()
    defer { watcher.stop() }

    try await Task.sleep(for: .milliseconds(200))
    try temp.writeFile("arrived.png")

    try await waitUntil(timeout: .seconds(5)) { box.names.contains("arrived.png") }

    #expect(box.names.contains("arrived.png"))
    #expect(box.count(of: "arrived.png") == 1)
    #expect(!box.names.contains("pre-existing.png"), "files present at start are not new")
}

@Test func watcherFlagsAFolderThatDoesNotExist() {
    let missing = URL(fileURLWithPath: "/tmp/ledge-missing-\(UUID().uuidString)")
    let watcher = FolderWatcher(folders: [missing]) { _ in }
    watcher.start()
    defer { watcher.stop() }

    #expect(watcher.unavailableFolders == [missing])
}

@Test func watcherDoesNotReemitFilesAfterFolderReappears() async throws {
    // A12: DirectorySnapshot(scanning:) reports an empty listing for a folder
    // that is gone. If the watcher stores that as the new baseline, then when
    // the folder reappears (the volume remounts, or something recreates it)
    // every pre-existing file looks "new" and gets re-emitted. This uses a
    // fast reconnectPollInterval and emptinessSettleDelay so the
    // reconnect-after-delete cycle below completes without depending on
    // production-sized cadences — real DispatchSource events cannot observe
    // the folder's return at all (a deleted directory's descriptor never sees
    // events for whatever is later created at the same path), so *some* poll
    // is unavoidable; only its speed is test-only.
    let temp = try TempDirectory()
    try temp.writeFile("pre-existing.png")

    let box = Box()
    let watcher = FolderWatcher(
        folders: [temp.url],
        onNewEntries: { urls in box.add(urls) },
        reconnectPollInterval: .milliseconds(20),
        emptinessSettleDelay: .milliseconds(30),
        reconnectLeeway: .milliseconds(5)
    )
    watcher.start()
    defer { watcher.stop() }

    // start() establishes the baseline synchronously, so the folder can be
    // removed immediately.
    try FileManager.default.removeItem(at: temp.url)

    try await waitUntil(timeout: .seconds(5)) { watcher.unavailableFolders.contains(temp.url) }

    // Recreate it with the same file, plus one genuinely new file.
    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    try "x".write(
        to: temp.url.appendingPathComponent("pre-existing.png"), atomically: true, encoding: .utf8)
    try "y".write(
        to: temp.url.appendingPathComponent("really-new.png"), atomically: true, encoding: .utf8)

    try await waitUntil(timeout: .seconds(5)) { box.names.contains("really-new.png") }

    #expect(box.names.contains("really-new.png"))
    #expect(box.count(of: "really-new.png") == 1)
    #expect(
        !box.names.contains("pre-existing.png"),
        "a file present before the folder vanished must not be re-emitted when it reappears")
}

@Test func watcherFlagsAFolderDeletedWhileAlreadyEmpty() async throws {
    // Finding 1: the plain existence guard at the top of rescan() looks
    // redundant against every other test here, because deleting a *non-empty*
    // folder always routes through the settle-delay branch (confirmEmptiness
    // has its own existence check). But a folder that is already empty when
    // it is deleted produces current.entries.isEmpty == previous.entries
    // .isEmpty == true, which never enters that branch at all — so this is
    // the only path that actually exercises the guard, and without it this
    // deletion would go completely unnoticed: never flagged unavailable,
    // never reconnected.
    let temp = try TempDirectory() // starts empty — no writeFile call
    let watcher = FolderWatcher(
        folders: [temp.url],
        onNewEntries: { _ in },
        reconnectPollInterval: .milliseconds(20),
        emptinessSettleDelay: .milliseconds(30),
        reconnectLeeway: .milliseconds(5)
    )
    watcher.start()
    defer { watcher.stop() }

    try FileManager.default.removeItem(at: temp.url)

    try await waitUntil(timeout: .seconds(5)) { watcher.unavailableFolders.contains(temp.url) }
    #expect(watcher.unavailableFolders.contains(temp.url))
}

@Test func watcherReportsEachFileExactlyOnce() async throws {
    // Finding 2: if a rescan ever failed to advance the stored baseline, every
    // later arrival would cause every earlier arrival to be re-reported too —
    // in production, Ledge would refile the same download two or three times
    // over (a second attempt landing as "rapor (1).pdf", a third as "rapor
    // (2).pdf"). A Set-based collector can't see that, since it can't count;
    // this asserts an exact count per file instead.
    let temp = try TempDirectory()
    let box = Box()
    let watcher = FolderWatcher(folders: [temp.url]) { urls in box.add(urls) }
    watcher.start()
    defer { watcher.stop() }

    try temp.writeFile("first.png")
    try await waitUntil(timeout: .seconds(5)) { box.names.contains("first.png") }

    try temp.writeFile("second.png")
    try await waitUntil(timeout: .seconds(5)) { box.names.contains("second.png") }

    #expect(box.count(of: "first.png") == 1)
    #expect(box.count(of: "second.png") == 1)
}

@Test func callbackCanSynchronouslyCallBackIntoTheWatcherWithoutDeadlocking() async throws {
    // Finding 3: onNewEntries used to run inline on the watcher's own private
    // queue. A callback that turns around and calls back into the watcher
    // synchronously — reading unavailableFolders, or calling stop() — does
    // queue.sync on the queue it is already running on, which always
    // deadlocks. Task 12's real callback happens to dodge this by hopping
    // through `Task { await ... }`, but that's luck, not a guarantee every
    // future caller will follow. This calls back with no such hop; if the
    // deadlock were still there, the callback would simply never complete,
    // and waitUntil below would time out rather than the test hanging
    // forever.
    final class Ref: @unchecked Sendable {
        private let lock = NSLock()
        private var watcher: FolderWatcher?
        func set(_ watcher: FolderWatcher) { lock.lock(); self.watcher = watcher; lock.unlock() }
        func get() -> FolderWatcher? { lock.lock(); defer { lock.unlock() }; return watcher }
    }

    let temp = try TempDirectory()
    let ref = Ref()
    let box = Box()
    let watcher = FolderWatcher(folders: [temp.url]) { urls in
        _ = ref.get()?.unavailableFolders
        box.add(urls)
    }
    ref.set(watcher)
    watcher.start()
    defer { watcher.stop() }

    try temp.writeFile("arrived.png")

    try await waitUntil(timeout: .seconds(5)) { box.names.contains("arrived.png") }
    #expect(
        box.names.contains("arrived.png"),
        "the callback must complete even though it calls back into the watcher")
}

@Test func reconnectTimerDoesNotRunWhenNothingIsUnavailable() throws {
    // Finding 4: the reconnect poll used to run unconditionally for the
    // watcher's whole lifetime — roughly 172,800 forced wakeups a day for an
    // empty loop, in an app whose entire point is to sit unnoticed.
    let temp = try TempDirectory()
    let watcher = FolderWatcher(folders: [temp.url]) { _ in }
    watcher.start()
    defer { watcher.stop() }

    #expect(!watcher.isReconnectTimerRunningForTesting, "nothing is missing, so the poll should not be running")
    #expect(watcher.unavailableFolders.isEmpty)
}

@Test func reconnectTimerStopsOnceEverythingReconnects() async throws {
    let missing = URL(fileURLWithPath: "/tmp/ledge-missing-\(UUID().uuidString)")
    let watcher = FolderWatcher(
        folders: [missing],
        onNewEntries: { _ in },
        reconnectPollInterval: .milliseconds(20),
        emptinessSettleDelay: .milliseconds(30),
        reconnectLeeway: .milliseconds(5)
    )
    watcher.start()
    defer { watcher.stop() }

    #expect(watcher.isReconnectTimerRunningForTesting, "a missing folder must keep the poll running")

    try FileManager.default.createDirectory(at: missing, withIntermediateDirectories: true)
    try await waitUntil(timeout: .seconds(5)) { watcher.unavailableFolders.isEmpty }

    try await waitUntil(timeout: .seconds(5)) { !watcher.isReconnectTimerRunningForTesting }
    #expect(!watcher.isReconnectTimerRunningForTesting, "the poll must stop once nothing is left to reconnect")
}

@Test func duplicateWatchedFolderDoesNotLeakADescriptor() async throws {
    // Finding 5a: a duplicate URL in `folders` used to overwrite watches[folder]
    // with a second descriptor/source without cancelling the first, leaking it
    // silently — the dictionary always shows one entry either way, so only
    // tracking real opens vs. real closes can see the leak.
    let temp = try TempDirectory()
    let watcher = FolderWatcher(folders: [temp.url, temp.url]) { _ in }
    watcher.start()
    watcher.stop()

    try await waitUntil(timeout: .seconds(5)) { watcher.descriptorLeakBalanceForTesting == 0 }
    #expect(
        watcher.descriptorLeakBalanceForTesting == 0,
        "a duplicated folder must not open a second, unclosed descriptor")
}

@Test func droppingTheWatcherWithoutStoppingClosesItsDescriptor() async throws {
    // Finding 5b: with no deinit, dropping a FolderWatcher without calling
    // stop() leaked its descriptor, source and repeating timer forever —
    // DispatchSource keeps a resumed-but-uncancelled source alive even after
    // every strong reference to it is gone.
    let temp = try TempDirectory()
    var watcher: FolderWatcher? = FolderWatcher(folders: [temp.url]) { _ in }
    watcher?.start()
    let descriptor = try #require(watcher?.descriptorForTesting(temp.url))
    #expect(isOpenDescriptor(descriptor))

    watcher = nil // dropped without calling stop()

    try await waitUntil(timeout: .seconds(5)) { !isOpenDescriptor(descriptor) }
    #expect(
        !isOpenDescriptor(descriptor),
        "dropping the watcher must close its descriptor even without an explicit stop()")
}

@Test func concurrentStartStopAndReadsDoNotCorruptState() async throws {
    // A11 requires every access to watches/snapshots/_unavailableFolders to be
    // serialized on the watcher's private queue. There is no way for an
    // ordinary assertion to deterministically force a data race to manifest
    // as a wrong VALUE — that is the nature of undefined behavior, and is
    // exactly why the mutation audit's finding ("all three queue.sync
    // mutations survive") is not itself proof of safety either way. What this
    // test does deterministically is hammer start()/stop()/unavailableFolders
    // concurrently from many tasks against one shared instance. Under Thread
    // Sanitizer:
    //   swift test --sanitize thread --filter concurrentStartStopAndReadsDoNotCorruptState
    // this reliably reports a data race the moment queue.sync is removed from
    // any of the three call sites in FolderWatcher.swift (start/stop/
    // unavailableFolders), and reports nothing with them present — see the
    // report for both transcripts. Without TSan, this test's own assertion
    // (no leaked descriptor after the dust settles) is a real but weaker
    // check: it can catch some corruption, not prove the absence of a race.
    let temp = try TempDirectory()
    let watcher = FolderWatcher(folders: [temp.url]) { _ in }

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<50 {
            group.addTask { watcher.start() }
            group.addTask { _ = watcher.unavailableFolders }
            group.addTask { watcher.stop() }
        }
    }

    watcher.stop()
    try await waitUntil(timeout: .seconds(5)) { watcher.descriptorLeakBalanceForTesting == 0 }
    #expect(watcher.descriptorLeakBalanceForTesting == 0)
}

// MARK: - helpers

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    func add(_ urls: Set<URL>) {
        lock.lock(); defer { lock.unlock() }
        for url in urls {
            counts[url.lastPathComponent, default: 0] += 1
        }
    }

    var names: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return Set(counts.keys)
    }

    func count(of name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return counts[name] ?? 0
    }
}

private func waitUntil(
    timeout: Duration,
    _ condition: @escaping () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
}

private func isOpenDescriptor(_ descriptor: Int32) -> Bool {
    fcntl(descriptor, F_GETFD) != -1
}
