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
        emptinessSettleDelay: .milliseconds(30)
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
    #expect(
        !box.names.contains("pre-existing.png"),
        "a file present before the folder vanished must not be re-emitted when it reappears")
}

// MARK: - helpers

private final class Box: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Set<String> = []

    func add(_ urls: Set<URL>) {
        lock.lock(); defer { lock.unlock() }
        storage.formUnion(urls.map(\.lastPathComponent))
    }

    var names: Set<String> {
        lock.lock(); defer { lock.unlock() }
        return storage
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
