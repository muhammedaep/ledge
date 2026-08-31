import Testing
import Foundation
@testable import LedgeCore

@Test(arguments: ["a.crdownload", "b.part", "c.partial", "d.download", "e.tmp", "f.opdownload", "g.!ut"])
func inProgressExtensionsAreIgnored(name: String) {
    #expect(DownloadSettler.isIgnored(URL(fileURLWithPath: "/tmp/\(name)")))
}

@Test func hiddenFilesAreIgnored() {
    #expect(DownloadSettler.isIgnored(URL(fileURLWithPath: "/tmp/.DS_Store")))
}

@Test func ordinaryFilesAreNotIgnored() {
    #expect(!DownloadSettler.isIgnored(URL(fileURLWithPath: "/tmp/report.pdf")))
    #expect(!DownloadSettler.isIgnored(URL(fileURLWithPath: "/tmp/no-extension")))
}

@Test func uppercaseExtensionIsIgnored() {
    #expect(DownloadSettler.isIgnored(URL(fileURLWithPath: "/tmp/big.CRDOWNLOAD")))
}

@Test func ignoredExtensionSettlesAsIgnoredWithoutWaiting() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("big.crdownload")
    let settler = DownloadSettler(sampleInterval: .milliseconds(10), ceiling: .seconds(1))

    let start = ContinuousClock.now
    let result = await settler.settle(url)
    let elapsed = start.duration(to: ContinuousClock.now)

    #expect(result == .ignored)
    #expect(elapsed < .milliseconds(50), "an ignored extension must return immediately, not wait through any sampling")
}

/// A `sizeProvider` that records how many times it was asked. How often a
/// settle samples is then a fact a test can assert directly, instead of
/// something inferred from how long the settle took.
private final class SizeReads: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private let size: Int64

    init(returning size: Int64) { self.size = size }

    func read(_ url: URL) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        count += 1
        return size
    }

    var callCount: Int { lock.lock(); defer { lock.unlock() }; return count }
}

@Test func aStableFileIsReady() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("report.pdf", contents: "done")

    // "A file that never changes settles on its first sample" is asserted here
    // as a fact about the outcome, not read off a stopwatch.
    //
    // `settle` tests its deadline only at the top of each iteration, so a
    // ceiling far *shorter* than one sample interval is survivable exactly
    // once: a settle that concludes on its first sample returns .ready however
    // slow the machine is, while one that needs a second sample finds the
    // deadline long past and reports .gaveUp. Load cannot turn one into the
    // other.
    //
    // This replaces an `elapsed < 80ms` assertion whose margin was gone —
    // measured over ten runs it sat at 51-56ms, and it failed in isolation at
    // 80.9ms.
    //
    // Worth recording why the ceiling, and not merely the read count, is what
    // carries this test. Seeding `previous` with a sentinel costs an extra
    // loop *iteration* but not an extra read: the read the seed would have
    // done simply moves inside the loop, so with a generous ceiling both the
    // real code and the bug make exactly two reads. Checked by mutation rather
    // than assumed — a count-only version of this test passes against the
    // sentinel. Under the short ceiling the bug is cut off mid-loop, so both
    // assertions below fire, the count now pinning sampling shape rather than
    // carrying the load alone.
    // The 20ms ceiling covers one thing that is not free of the clock: the gap
    // between computing the deadline and the loop's first check of it, which is
    // a single closure call. A scheduler stall longer than that yields a
    // spurious .gaveUp — deliberately the safe direction, because it makes this
    // test *fail* rather than pass for the wrong reason. Do not "fix" such a
    // failure by widening the ceiling: past one sample interval it stops
    // discriminating at all, and the load-dependence this construction exists
    // to remove comes straight back.
    let reads = SizeReads(returning: 4)
    let settler = DownloadSettler(
        sampleInterval: .milliseconds(200),
        ceiling: .milliseconds(20),
        sizeProvider: { reads.read($0) }
    )

    let result = await settler.settle(url)

    #expect(result == .ready, "a stable file must conclude on its first sample, before the ceiling")
    #expect(reads.callCount == 2, "one seeding read before the loop, plus the one sample inside it")
}

@Test func fileSizeReflectsGrowthAsTheFileIsWrittenTo() throws {
    // A direct test of DownloadSettler.fileSize itself, on the real
    // filesystem: this is what actually guards against reintroducing the
    // URL.resourceValues caching bug (see its doc comment), independent of
    // any settle() timing.
    let temp = try TempDirectory()
    let url = try temp.writeFile("growing-direct.bin", contents: "0")

    let before = DownloadSettler.fileSize(url)
    try String(repeating: "x", count: 500).write(to: url, atomically: false, encoding: .utf8)
    let after = DownloadSettler.fileSize(url)

    #expect(before == 1)
    #expect(after == 500)
}

@Test func fileSizeSentinelForAMissingPathIsNegativeOne() throws {
    // No settle() codepath currently calls fileSize a second time on a path
    // that has already vanished — both the top-level and in-loop fileExists
    // guards intercept first — so this sentinel value is otherwise untested
    // by anything else in this file. A direct assertion, not an elapsed-time
    // one, since there is no "slower vs faster" behavior to time here: the
    // fallback is either right or silently wrong.
    let temp = try TempDirectory()
    let url = temp.url.appendingPathComponent("never-written.bin")
    #expect(DownloadSettler.fileSize(url) == -1)
}

@Test func aGrowingFileIsNotReadyUntilItStops() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("growing.bin", contents: "0")

    // Writes immediately, then keeps writing well faster than the settler
    // samples (5ms writes against a 20ms sampleInterval below): several
    // writes land inside every sampling window, so an occasional delayed
    // write under concurrent-suite load can't cause a false early match.
    // 30 writes keep the file changing for ~150ms, comfortably past the
    // 100ms floor asserted below.
    let writer = Task {
        for i in 1...30 {
            try? String(repeating: "x", count: i * 100).write(to: url, atomically: false, encoding: .utf8)
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    let settler = DownloadSettler(sampleInterval: .milliseconds(20), ceiling: .seconds(5))
    let start = ContinuousClock.now
    let result = await settler.settle(url)
    let elapsed = start.duration(to: ContinuousClock.now)
    await writer.value

    #expect(result == .ready, "should have waited for writing to stop, then reported ready")
    #expect(
        elapsed >= .milliseconds(100),
        "must have actually observed growth across several samples before settling, not concluded ready immediately"
    )
}

@Test func aFileThatNeverStopsGrowingGivesUpAtTheCeiling() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("endless.bin", contents: "0")

    // A size that is always different from the last reading — no writer
    // thread and no timing race against the settler's own sampling clock,
    // so this is deterministic on every machine.
    final class IncreasingCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64 = 0
        func next() -> Int64 {
            lock.lock(); defer { lock.unlock() }
            value += 1
            return value
        }
    }
    let counter = IncreasingCounter()

    let settler = DownloadSettler(
        sampleInterval: .milliseconds(5),
        ceiling: .milliseconds(120),
        sizeProvider: { _ in counter.next() }
    )
    let result = await settler.settle(url)

    #expect(result == .gaveUp)
}

/// Set once, readable from another thread.
private final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var value = true
    func lower() { lock.lock(); value = false; lock.unlock() }
    var isRaised: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

@Test(.timeLimit(.minutes(1)))
func aFileAnotherAppIsOnlyReadingIsReady() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("shared.pdf", contents: "done")

    // Another app holds a *reading* claim on the file — Preview has the PDF
    // open, say. Reading claims do not conflict with each other, so this must
    // settle without waiting. Asking the question with a *writing* intent
    // instead would both block on this claim and, worse, take a write claim of
    // Ledge's own on a file it has merely been asked to look at, locking out
    // every other reader of the user's document to answer "is it finished?".
    //
    // The assertion is an ordering fact, not a stopwatch reading: did the
    // settle finish while the claim was still held? Elapsed-time thresholds
    // are not trustworthy here — a coordinated read on a loaded machine has
    // been measured taking most of a second with nothing contending at all.
    let claimHeld = Latch()
    let release = DispatchSemaphore(value: 0)
    nonisolated(unsafe) let readerCoordinator = NSFileCoordinator()

    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let readerThread = Thread {
            var error: NSError?
            readerCoordinator.coordinate(readingItemAt: url, options: [], error: &error) { _ in
                continuation.resume()
                // Held until the settle is done — or, if a mutant is waiting on
                // this claim rather than ignoring it, until this backstop fires
                // so the suite fails rather than hangs.
                _ = release.wait(timeout: .now() + 5.0)
                claimHeld.lower()
            }
        }
        readerThread.start()
    }
    defer { release.signal() }

    let settler = DownloadSettler(sampleInterval: .milliseconds(20), ceiling: .seconds(30))
    let result = await settler.settle(url)

    #expect(result == .ready)
    #expect(claimHeld.isRaised,
            "the check must not wait out a reader's claim; a writing intent would have to")
}

// A settle that never resumes its continuation does not fail this test, it
// hangs it — and a hung suite is worse than a failing one, because it reports
// nothing at all. The limit is the coarsest Swift Testing allows.
@Test(.timeLimit(.minutes(1)))
func aCancelledSettleReturnsPromptlyInsteadOfSpinning() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("cancel-me.bin", contents: "0")

    // A size that never repeats, so without the cancellation check the
    // settler would never conclude .ready on its own either — it would keep
    // sampling, uninterrupted, until the ceiling below.
    final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count: Int64 = 0
        func next() -> Int64 {
            lock.lock(); defer { lock.unlock() }
            count += 1
            return count
        }
        var callCount: Int64 { lock.lock(); defer { lock.unlock() }; return count }
    }
    let counter = CallCounter()

    // A deliberately long ceiling: if cancellation were not honored, the
    // settle below would busy-spin (Task.sleep resolves instantly once
    // cancelled) all the way to this deadline, sampling continuously.
    let settler = DownloadSettler(
        sampleInterval: .milliseconds(5),
        ceiling: .seconds(2),
        sizeProvider: { _ in counter.next() }
    )

    let settling = Task { await settler.settle(url) }
    try await Task.sleep(for: .milliseconds(25))
    settling.cancel()

    let start = ContinuousClock.now
    let result = await settling.value
    let elapsed = start.duration(to: ContinuousClock.now)

    #expect(result == .cancelled, "a cancelled settle reached no conclusion; the caller may re-queue it")
    #expect(elapsed < .milliseconds(500), "a cancelled settle should return promptly, not spin until the ceiling")
    #expect(counter.callCount < 100, "a cancelled settle should not keep sampling after cancellation")
}

/// A one-shot signal that synchronous code can raise and an async test can
/// await, without blocking a cooperative thread on a semaphore.
private final class Signal: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false
    private var waiter: CheckedContinuation<Void, Never>?

    func raise() {
        lock.lock()
        guard !raised else { lock.unlock(); return }
        raised = true
        let waiting = waiter
        waiter = nil
        lock.unlock()
        waiting?.resume()
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if raised {
                lock.unlock()
                continuation.resume()
            } else {
                waiter = continuation
                lock.unlock()
            }
        }
    }
}

@Test(.timeLimit(.minutes(1)))
func aContendedFileIsReportedStillWritingNotReady() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("contended.bin", contents: "done")

    // Hold a real writing claim on a dedicated OS thread, simulating another
    // app (or iCloud) actively writing this same file — a coordinated read
    // against an active write claim does not fail fast, it waits for the
    // claim to be released (confirmed by direct experiment), so this is the
    // only way to exercise canReadWithoutContention's false path for real.
    // NSFileCoordinator predates Sendable; cancelling/signaling it across
    // threads is exactly its documented purpose.
    //
    // The claim is held until this test releases it, with a 2s backstop. That
    // number is load-bearing in one direction only and must not be raised: the
    // implementation this test replaced waited on a semaphore with a *3 second*
    // timeout and ignored cancellation entirely, so the claim has to fall away
    // before that timeout for the difference to show up in the result. It is
    // not a deadline the correct implementation ever approaches — it returns in
    // tens of milliseconds.
    let claimHeld = Latch()
    let releaseWriter = DispatchSemaphore(value: 0)
    nonisolated(unsafe) let writerCoordinator = NSFileCoordinator()
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let writerThread = Thread {
            var error: NSError?
            writerCoordinator.coordinate(writingItemAt: url, options: [], error: &error) { _ in
                continuation.resume()
                _ = releaseWriter.wait(timeout: .now() + 2.0)
                claimHeld.lower()
            }
        }
        writerThread.start()
    }
    defer { releaseWriter.signal() }

    // THE SYNCHRONISATION — please do not turn this back into a sleep.
    //
    // This test must cancel the settle *after* it has committed to the
    // coordinated read. Waiting a fixed 60ms for that was wrong, and failed
    // about one full-suite run in ten: under load the cancel landed while the
    // settler was still in its sampling loop, where `Task.isCancelled` quite
    // correctly returns .cancelled, and the test blamed the code.
    //
    // The injected sizeProvider is the fact we need. `settle` reads the size
    // once to seed `previous`, then once per sample; the second read is the one
    // compared against the seed, and because the sizes match, the very next
    // thing it does is enter canReadWithoutContention. Crucially there is no
    // `Task.isCancelled` check between that read and the coordinated read, so
    // once the second read has happened `.cancelled` is off the table and the
    // outcome can only be .ready or .stillWriting. Waiting for that read is
    // therefore exact, and immune to how loaded the machine is.
    let committedToCoordinatedRead = Signal()
    let reads = SizeReads(returning: 4)
    let settler = DownloadSettler(
        sampleInterval: .milliseconds(20),
        ceiling: .seconds(30),
        sizeProvider: { url in
            let size = reads.read(url)
            if reads.callCount == 2 { committedToCoordinatedRead.raise() }
            return size
        }
    )

    let settling = Task { await settler.settle(url) }
    await committedToCoordinatedRead.wait()
    settling.cancel()
    let result = await settling.value

    #expect(result == .stillWriting,
            "contention must not be reported as ready, whether resolved or cut short by cancellation")
    // The second assertion is an ordering fact rather than a stopwatch reading:
    // a cancelled coordinated read must come back while the other claim is
    // still held. An implementation that cannot be cancelled comes back only
    // once the writer has let go, by which point this latch is down.
    #expect(claimHeld.isRaised,
            "a cancelled contended read must not wait out the other claim")
}

@Test func aFileDeletedDuringSettlingIsIgnoredNotReady() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("vanishing.bin", contents: "0")

    // Deliberately no injected sizeProvider: the default DownloadSettler.fileSize
    // returns -1 for a path that no longer exists, and two -1 reads compare
    // equal — this is exactly what the in-loop fileExists guard must catch
    // before the size comparison ever runs. A long sampleInterval keeps the
    // settler asleep through its first sample window until well after the
    // deletion below, so the guard — not a lucky size mismatch — is what's
    // under test.
    let settler = DownloadSettler(sampleInterval: .milliseconds(200), ceiling: .seconds(2))

    let settling = Task { await settler.settle(url) }
    try await Task.sleep(for: .milliseconds(20))
    try FileManager.default.removeItem(at: url)

    let result = await settling.value
    #expect(result == .ignored, "a file that disappears mid-settle must not be reported ready")
}

@Test func aVanishedFileIsIgnored() async throws {
    let temp = try TempDirectory()
    let url = temp.url.appendingPathComponent("never-existed.pdf")
    // A 100ms sampleInterval, well above the immediate-return floor below: a
    // file that never existed must be caught by the top-level fileExists
    // guard before ever entering the sampling loop. If that guard were
    // dropped, the in-loop guard would still eventually catch it, but only
    // after one full sampleInterval — the elapsed assertion distinguishes
    // "caught immediately" from "caught one sample late."
    let settler = DownloadSettler(sampleInterval: .milliseconds(100), ceiling: .seconds(1))

    let start = ContinuousClock.now
    let result = await settler.settle(url)
    let elapsed = start.duration(to: ContinuousClock.now)

    #expect(result == .ignored)
    #expect(elapsed < .milliseconds(50), "a file that never existed must be caught before the sampling loop, not inside it")
}
