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
    let settler = DownloadSettler(sampleInterval: .milliseconds(20), ceiling: .seconds(2))
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

    // Writes continuously on its own OS thread, off Swift's cooperative
    // executor, so it can't be starved by the other tests running concurrently
    // on that shared pool while this test is timing the settler's polling loop.
    final class StopFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false
        func stop() { lock.lock(); stopped = true; lock.unlock() }
        var isStopped: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    }
    let stopFlag = StopFlag()
    let writerThread = Thread {
        var i = 0
        while !stopFlag.isStopped {
            i += 1
            try? String(repeating: "x", count: i * 100).write(to: url, atomically: false, encoding: .utf8)
        }
    }
    writerThread.start()

    let settler = DownloadSettler(sampleInterval: .milliseconds(5), ceiling: .milliseconds(120))
    let result = await settler.settle(url)
    stopFlag.stop()

    #expect(result == .gaveUp)
}

@Test func aVanishedFileIsIgnored() async throws {
    let temp = try TempDirectory()
    let url = temp.url.appendingPathComponent("never-existed.pdf")
    let settler = DownloadSettler(sampleInterval: .milliseconds(10), ceiling: .seconds(1))
    #expect(await settler.settle(url) == .ignored)
}
