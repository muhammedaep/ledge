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

@Test func aStableFileIsReady() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("report.pdf", contents: "done")
    let settler = DownloadSettler(
        sampleInterval: .milliseconds(20),
        ceiling: .seconds(2),
        sizeProvider: { _ in 4 }
    )
    #expect(await settler.settle(url) == .ready)
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

@Test func aCancelledSettleReturnsPromptlyInsteadOfSpinning() async throws {
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
    let settler = DownloadSettler(sampleInterval: .milliseconds(10), ceiling: .seconds(1))
    #expect(await settler.settle(url) == .ignored)
}
