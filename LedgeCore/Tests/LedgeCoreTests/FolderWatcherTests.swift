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

@Test func stopCancelsTheReconnectTimerEvenWhileAFolderIsUnavailable() throws {
    // Finding 3 (round 4): stopLocked already cancels reconnectTimer, but
    // nothing asserted that directly for the case that actually matters —
    // stop() called while a folder is still missing. Without that cancel, a
    // watcher stopped mid-outage would keep waking the machine every
    // reconnectPollInterval forever, never noticing it was supposed to be
    // dead. (Checked first: this production code path already cancels the
    // timer — see stopLocked in FolderWatcher.swift — so this is a coverage
    // gap, not a live lifecycle bug.)
    let missing = URL(fileURLWithPath: "/tmp/ledge-missing-\(UUID().uuidString)")
    let watcher = FolderWatcher(folders: [missing]) { _ in }
    watcher.start()

    #expect(watcher.isReconnectTimerRunningForTesting, "a missing folder must start the poll")

    watcher.stop()

    #expect(
        !watcher.isReconnectTimerRunningForTesting,
        "stop() must cancel the reconnect poll even while a folder is unavailable")
}

@Test func waitUntilRecordsAnIssueRatherThanReturningSilentlyOnTimeout() async throws {
    // Finding 2 (round 4): waitUntil used to return silently once its
    // timeout elapsed with the condition still false — this surfaced when
    // an unrelated mutation made a condition never become true and the
    // whole 18-test file went from 1.7s to 6.6s and *still passed*. A
    // helper that turns a hung condition into a quiet wait can disarm
    // every test that uses it, invisibly. withKnownIssue fails this test
    // if `waitUntil` does NOT record an issue inside it — i.e. it would
    // have caught the old silent-return behavior directly.
    await withKnownIssue("a condition that never becomes true must record an issue, not return quietly") {
        try await waitUntil(timeout: .milliseconds(50)) { false }
    }
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
    //
    // Round 3, finding 4: checking only the descriptor *number* is flaky
    // under Swift Testing's default parallel execution — fd 3 tends to be
    // the lowest free descriptor, so it can be re-grabbed by an unrelated
    // concurrent test's open() inside the polling gap, making a stale
    // captured number look "still open" by coincidence. Serializing this
    // test wouldn't fix it (Swift Testing parallelizes the whole process,
    // not just this file), and comparing descriptorLeakBalanceForTesting
    // can't either (the watcher is already deallocated by the time we'd
    // check). Checking the descriptor's *identity* — what path it actually
    // points at, via F_GETPATH — is immune to both: a closed descriptor
    // fails outright, and a reused one resolves to a different path.
    let temp = try TempDirectory()
    var watcher: FolderWatcher? = FolderWatcher(folders: [temp.url]) { _ in }
    watcher?.start()
    let descriptor = try #require(watcher?.descriptorForTesting(temp.url))
    #expect(isDescriptorOpenOnFolder(descriptor, at: temp.url))

    watcher = nil // dropped without calling stop()

    try await waitUntil(timeout: .seconds(5)) { !isDescriptorOpenOnFolder(descriptor, at: temp.url) }
    #expect(
        !isDescriptorOpenOnFolder(descriptor, at: temp.url),
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

@Test func noEmissionArrivesAfterStopReturns() async throws {
    // Finding 1 (round 2): dispatching the callback off `queue` fixed the
    // deadlock but traded it for a lifecycle hole — a delivery already
    // scheduled when stop() is called could still land afterwards, e.g.
    // mid-restart, filing an arrival against whatever folder wins the race.
    // A queue-confined generation counter (bumped by stopLocked, which both
    // start() and stop() go through) is captured when a delivery is
    // scheduled and re-checked when it actually runs; a stale delivery is
    // dropped.
    //
    // To observe this deterministically: the "first.png" callback blocks on
    // a semaphore before recording anything, so the test can be sure a
    // second, already-scheduled delivery for "second.png" is still sitting
    // behind it on the (now serial) delivery queue — not racing to complete
    // before stop() can bump the generation. The only timing dependency left
    // is "did the real write event for second.png get processed by `queue`
    // within 500ms" — unrelated to, and unblocked by, the stalled delivery
    // queue, and generous given every other real-event test in this file
    // observes delivery within a few hundred milliseconds at most.
    let temp = try TempDirectory()
    let box = Box()
    let releaseFirst = DispatchSemaphore(value: 0)
    let firstArrived = DispatchSemaphore(value: 0)
    defer { releaseFirst.signal() } // never leave the delivery queue's worker blocked

    let watcher = FolderWatcher(folders: [temp.url]) { urls in
        if urls.contains(where: { $0.lastPathComponent == "first.png" }) {
            firstArrived.signal()
            releaseFirst.wait()
        }
        box.add(urls)
    }
    watcher.start()
    defer { watcher.stop() }

    try temp.writeFile("first.png")
    try #require(blockingWait(firstArrived, timeout: .now() + 5) == .success)

    try temp.writeFile("second.png")
    try await Task.sleep(for: .milliseconds(500))

    watcher.stop() // bumps the generation while "second.png"'s delivery is still queued, unstarted
    releaseFirst.signal() // let "first.png" finish; the delivery queue then reaches "second.png"

    try await Task.sleep(for: .milliseconds(300))
    #expect(!box.names.contains("second.png"), "a delivery scheduled before stop() must not land after it")
}

@Test func secondMissingFolderStaysReconnectableAfterFirstReconnects() async throws {
    // Finding 3a: stopReconnectTimerLockedIfIdle's `_unavailableFolders
    // .isEmpty` guard matters as soon as more than one folder can be
    // unavailable at once — without it, any single folder reconnecting would
    // stop the poll outright, orphaning every other still-missing folder,
    // exactly like finding 1 from round one, just multiplied.
    let missingA = URL(fileURLWithPath: "/tmp/ledge-missing-a-\(UUID().uuidString)")
    let missingB = URL(fileURLWithPath: "/tmp/ledge-missing-b-\(UUID().uuidString)")
    defer {
        try? FileManager.default.removeItem(at: missingA)
        try? FileManager.default.removeItem(at: missingB)
    }

    let box = Box()
    let watcher = FolderWatcher(
        folders: [missingA, missingB],
        onNewEntries: { urls in box.add(urls) },
        reconnectPollInterval: .milliseconds(20),
        emptinessSettleDelay: .milliseconds(30),
        reconnectLeeway: .milliseconds(5)
    )
    watcher.start()
    defer { watcher.stop() }

    #expect(Set(watcher.unavailableFolders) == [missingA, missingB])
    #expect(watcher.isReconnectTimerRunningForTesting)

    try FileManager.default.createDirectory(at: missingA, withIntermediateDirectories: true)
    try await waitUntil(timeout: .seconds(5)) { !watcher.unavailableFolders.contains(missingA) }

    // missingB is still gone — the poll must still be running for it.
    #expect(watcher.isReconnectTimerRunningForTesting, "a second missing folder must keep the poll alive")
    #expect(watcher.unavailableFolders.contains(missingB))

    try FileManager.default.createDirectory(at: missingB, withIntermediateDirectories: true)
    try await waitUntil(timeout: .seconds(5)) { !watcher.unavailableFolders.contains(missingB) }

    try "x".write(to: missingB.appendingPathComponent("proof.png"), atomically: true, encoding: .utf8)
    try await waitUntil(timeout: .seconds(5)) { box.names.contains("proof.png") }
    #expect(box.names.contains("proof.png"), "the second folder must still be reconnected and watched")
}

@Test func duplicateWatchedFolderStillDetectsNewFiles() async throws {
    // Finding 3b: the fd-balance test alone doesn't prove the surviving watch
    // is actually live — a wrong "fix" could cancel the right descriptor
    // (balance reads zero) while leaving `watches[folder]` pointing at the
    // now-dead source, silently unwatching the folder without ever flagging
    // it unavailable. This proves the watch that
    // duplicateWatchedFolderDoesNotLeakADescriptor leaves behind still
    // actually detects new files, not just that its fd count balances.
    let temp = try TempDirectory()
    let box = Box()
    let watcher = FolderWatcher(folders: [temp.url, temp.url]) { urls in box.add(urls) }
    watcher.start()
    defer { watcher.stop() }

    try temp.writeFile("arrived.png")
    try await waitUntil(timeout: .seconds(5)) { box.names.contains("arrived.png") }

    #expect(box.count(of: "arrived.png") == 1)
}

@Test func descriptorBalanceStaysZeroWhileFolderIsUnavailable() async throws {
    // Finding 3c: without source.cancel() in markMissingLocked, every folder
    // disappearance leaks one descriptor. Measured directly via the leak
    // balance rather than only inferred from unavailableFolders, since the
    // balance is what actually tracks the real OS resource.
    let temp = try TempDirectory()
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

    try await waitUntil(timeout: .seconds(5)) { watcher.descriptorLeakBalanceForTesting == 0 }
    #expect(
        watcher.descriptorLeakBalanceForTesting == 0,
        "a folder going unavailable must close its old descriptor, not leak it")
}

@Test func stopDuringAPendingEmptinessSettleDoesNotResurrectTheWatcher() async throws {
    // Finding 1 (round 3, Critical): confirmEmptiness is scheduled via
    // queue.asyncAfter from rescan() and, before this fix, was not
    // generation-guarded — round 2's generation counter only protected
    // delivery. If that closure fires after stop() has already torn
    // everything down, it calls markMissingLocked, which calls
    // ensureReconnectTimerLocked — re-arming the reconnect poll on a
    // watcher that is supposed to be dead. Unlike the delivery bug this
    // isn't a one-shot stale event: once the poll is re-armed it keeps
    // running and can reconnect and emit again, unbounded in time.
    //
    // Sequence, driven by real events but synchronized on actual observed
    // state transitions rather than guessed timing (this file's tests run
    // in parallel by default, and this scenario turned out to be genuinely
    // sensitive to that — see the two false negatives noted below, both
    // found empirically, not hypothesized):
    //
    // empty the folder and remove the (now-empty) directory as two
    // separate, well-spaced steps — not one FileManager.removeItem(at:)
    // call on the whole directory. That single call's two underlying events
    // (unlink the child, then rmdir the directory) can coalesce under
    // contention, skipping the settle branch entirely and defeating this
    // test outright — confirmed by instrumenting the production code
    // temporarily and observing it happen.
    //
    // wait for hasPendingEmptinessSettleForTesting rather than a fixed
    // sleep before removing the directory: a fixed "should be enough" delay
    // was itself unreliable under contention (also confirmed by
    // instrumentation — the settle check ended up firing while the folder
    // still, correctly, existed, because the directory removal below had
    // not happened yet by the time the fixed delay elapsed and the wrong
    // real-world moment got captured as "now"). Waiting for the actual
    // scheduling signal removes that guesswork.
    //
    // Then: stop() promptly, while the settle check is still pending; wait
    // for hasPendingEmptinessSettleForTesting to clear (the check has
    // actually run, whatever its outcome) rather than sleeping past the
    // settle delay; then recreate the folder and write a file — if the poll
    // got resurrected, it reconnects and reports it.
    //
    // Round 4: waitUntil now fails loudly on timeout (finding 2) instead of
    // returning silently, and that surfaced a real, understood latency
    // source here that used to be masked: `concurrentStartAndDeliveryGenerationChecksDoNotRace`,
    // elsewhere in this file, deliberately saturates the process for a
    // fixed 3-second window (that's what makes its own race reproducible),
    // and this file's tests run in parallel by default. A real filesystem
    // event landing on `queue` can be delayed for the length of that
    // window under bad scheduling luck. The waits below use 15s — 5x that
    // known, bounded window — rather than an arbitrary bump; confirmed by
    // running the full suite repeatedly afterward (see the report) rather
    // than assumed.
    let temp = try TempDirectory()
    try temp.writeFile("pre-existing.png")

    let box = Box()
    let watcher = FolderWatcher(
        folders: [temp.url],
        onNewEntries: { urls in box.add(urls) },
        reconnectPollInterval: .milliseconds(20),
        emptinessSettleDelay: .milliseconds(200),
        reconnectLeeway: .milliseconds(5)
    )
    watcher.start()

    try FileManager.default.removeItem(at: temp.url.appendingPathComponent("pre-existing.png"))
    try await waitUntil(timeout: .seconds(15)) { watcher.hasPendingEmptinessSettleForTesting }

    try FileManager.default.removeItem(at: temp.url) // now a clean single-step removal of an already-empty directory
    try await waitUntil(timeout: .seconds(15)) { watcher.unavailableFolders.contains(temp.url) }

    watcher.stop()

    try await waitUntil(timeout: .seconds(15)) { !watcher.hasPendingEmptinessSettleForTesting }

    #expect(watcher.descriptorLeakBalanceForTesting == 0, "a stopped watcher must not reopen a descriptor")

    try FileManager.default.createDirectory(at: temp.url, withIntermediateDirectories: true)
    try await Task.sleep(for: .milliseconds(1500)) // time for a resurrected poll (20ms interval) to reconnect

    try "z".write(to: temp.url.appendingPathComponent("after-stop.png"), atomically: true, encoding: .utf8)
    try await Task.sleep(for: .milliseconds(1500)) // time for a resurrected live watch to report it

    #expect(watcher.descriptorLeakBalanceForTesting == 0, "a stopped watcher must not reopen a descriptor")
    #expect(!box.names.contains("after-stop.png"), "a stopped watcher must not resurrect and emit")
}

@Test func noEmissionArrivesAfterARestartViaStartAlone() async throws {
    // Finding 2 (round 3): AppState restarts this watcher by calling
    // start() again — there is no separate stop() call on that path. The
    // generation must be bumped there too, not only somewhere reachable
    // exclusively from stop(). Same blocking technique as
    // noEmissionArrivesAfterStopReturns, but the restart is start() alone.
    let temp = try TempDirectory()
    let box = Box()
    let releaseFirst = DispatchSemaphore(value: 0)
    let firstArrived = DispatchSemaphore(value: 0)
    defer { releaseFirst.signal() }

    let watcher = FolderWatcher(folders: [temp.url]) { urls in
        if urls.contains(where: { $0.lastPathComponent == "first.png" }) {
            firstArrived.signal()
            releaseFirst.wait()
        }
        box.add(urls)
    }
    watcher.start()
    defer { watcher.stop() }

    try temp.writeFile("first.png")
    try #require(blockingWait(firstArrived, timeout: .now() + 5) == .success)

    try temp.writeFile("second.png")
    try await Task.sleep(for: .milliseconds(500))

    watcher.start() // restart via start() alone, no explicit stop() first

    releaseFirst.signal()
    try await Task.sleep(for: .milliseconds(300))

    #expect(
        !box.names.contains("second.png"),
        "a delivery scheduled before a start()-triggered restart must not land after it")
}

@Test func concurrentStartAndDeliveryGenerationChecksDoNotRace() async throws {
    // Finding 3 (round 3), fixed in round 4: the delivery closure's
    // generation check deliberately reads `self.generation` via
    // `queue.sync` so that read is synchronized against concurrent bumps
    // from start()/stop(). A plain, unsynchronized read is a real data race
    // that ordinary testing does not reliably surface, because a torn read
    // of an Int rarely produces an externally observable wrong value. Under
    // Thread Sanitizer:
    //   swift test --sanitize thread --filter concurrentStartAndDeliveryGenerationChecksDoNotRace
    //
    // Round 3's construction (a tight, unpaced start() loop) never actually
    // exercised the mutated line: restarting that fast re-baselines
    // `snapshots` on every iteration (attachLocked takes a fresh scan as
    // the baseline whenever it isn't a reconnect), so by the time any
    // write's rescan runs, its files are already folded into the baseline
    // and `newEntries` is empty — commitLocked returns at
    // `guard !new.isEmpty` before ever reaching `deliveryQueue.async`. A
    // counter at the guard measured zero reads under that construction; it
    // was structurally incapable of failing regardless of the mutation.
    //
    // Fixed by pacing the restarts so real deliveries have room to form
    // between them: one task calls start() roughly every 500 microseconds
    // rather than as fast as possible, while another writes files
    // unthrottled for the same 3-second window — long enough for files
    // written between two starts to be diffed as genuinely new before the
    // next start() resets the baseline again.
    let temp = try TempDirectory()
    let folderURL = temp.url // a plain Sendable URL, unlike TempDirectory itself
    let watcher = FolderWatcher(folders: [temp.url]) { _ in }
    watcher.start()
    defer { watcher.stop() }

    let deadline = Date().addingTimeInterval(3)
    await withTaskGroup(of: Void.self) { group in
        group.addTask {
            while Date() < deadline {
                watcher.start()
                usleep(500)
            }
        }
        group.addTask {
            var i = 0
            while Date() < deadline {
                let fileURL = folderURL.appendingPathComponent("race-\(i).png")
                try? "x".write(to: fileURL, atomically: true, encoding: .utf8)
                i += 1
            }
        }
    }

    watcher.stop()
    try await waitUntil(timeout: .seconds(10)) { watcher.descriptorLeakBalanceForTesting == 0 }
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

/// Polls `condition` until it becomes true or `timeout` elapses.
///
/// Round 4, finding 2: this used to return silently on timeout — a
/// mutation elsewhere once made a condition never become true, and the
/// affected test just got slower (1.7s -> 6.6s) while still passing. A
/// helper that turns a hung condition into a quiet wait can disarm every
/// test that uses it, invisibly. It now records a failure via
/// `Issue.record` instead, so a timeout is a red test, not a slow green
/// one. `sourceLocation` defaults to the call site (not this line) so the
/// failure points at the test that actually hung, matching how `#expect`
/// already behaves.
private func waitUntil(
    timeout: Duration,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: @escaping () -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    if condition() { return }
    Issue.record("waitUntil timed out after \(timeout)", sourceLocation: sourceLocation)
}

/// Whether `descriptor` is currently open on `url`, checked by identity
/// (F_GETPATH) rather than by merely being a valid descriptor number — a
/// closed number can be immediately reassigned to something unrelated by a
/// concurrently running test, which a plain `fcntl(_, F_GETFD)` liveness
/// check can't distinguish from the original still being open.
private func isDescriptorOpenOnFolder(_ descriptor: Int32, at url: URL) -> Bool {
    var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
    guard fcntl(descriptor, F_GETPATH, &buffer) != -1 else { return false }
    let path = buffer.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
    return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        == url.resolvingSymlinksInPath().path
}

/// `DispatchSemaphore.wait` is unavailable directly inside an `async`
/// function body (it would block a cooperative-pool thread) — this
/// synchronous wrapper is the sanctioned way to still use one deliberately,
/// off the async call site, to synchronize with a background callback.
private func blockingWait(_ semaphore: DispatchSemaphore, timeout: DispatchTime) -> DispatchTimeoutResult {
    semaphore.wait(timeout: timeout)
}
