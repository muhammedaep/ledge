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

@Test func ignoredExtensionSettlesAsIgnoredWithoutWaiting() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("big.crdownload")
    let settler = DownloadSettler(sampleInterval: .milliseconds(10), ceiling: .seconds(1))
    #expect(await settler.settle(url) == .ignored)
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

@Test func aGrowingFileIsNotReadyUntilItStops() async throws {
    let temp = try TempDirectory()
    let url = try temp.writeFile("growing.bin", contents: "0")

    let writer = Task {
        for i in 1...4 {
            try? await Task.sleep(for: .milliseconds(25))
            try? String(repeating: "x", count: i * 500).write(to: url, atomically: false, encoding: .utf8)
        }
    }

    let settler = DownloadSettler(sampleInterval: .milliseconds(20), ceiling: .seconds(5))
    let result = await settler.settle(url)
    await writer.value

    #expect(result == .ready, "should have waited for writing to stop, then reported ready")
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

@Test func aVanishedFileIsIgnored() async throws {
    let temp = try TempDirectory()
    let url = temp.url.appendingPathComponent("never-existed.pdf")
    let settler = DownloadSettler(sampleInterval: .milliseconds(10), ceiling: .seconds(1))
    #expect(await settler.settle(url) == .ignored)
}
