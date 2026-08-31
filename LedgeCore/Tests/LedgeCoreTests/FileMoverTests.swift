import Testing
import Foundation
@testable import LedgeCore

@Test func movesFileIntoDestination() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png")
    let dest = temp.url.appendingPathComponent("Images", isDirectory: true)

    let final = try FileMover().move(source, into: dest)

    #expect(final == dest.appendingPathComponent("a.png"))
    #expect(FileManager.default.fileExists(atPath: final.path))
    #expect(!FileManager.default.fileExists(atPath: source.path))
}

@Test func createsDestinationFolderWhenMissing() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png")
    let dest = temp.url.appendingPathComponent("Images/PNG", isDirectory: true)

    let final = try FileMover().move(source, into: dest)
    #expect(FileManager.default.fileExists(atPath: final.path))
}

@Test func neverOverwritesAnExistingFile() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    try "original".write(to: dest.appendingPathComponent("a.png"), atomically: true, encoding: .utf8)
    let source = try temp.writeFile("a.png", contents: "incoming")

    let final = try FileMover().move(source, into: dest)

    #expect(final.lastPathComponent == "a (1).png")
    let untouched = try String(contentsOf: dest.appendingPathComponent("a.png"), encoding: .utf8)
    #expect(untouched == "original")
    #expect(try String(contentsOf: final, encoding: .utf8) == "incoming")
}

@Test func collisionCounterKeepsClimbing() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let mover = FileMover()

    for _ in 0..<3 {
        let source = try temp.writeFile("a.png")
        _ = try mover.move(source, into: dest)
    }

    let names = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
    #expect(names == ["a (1).png", "a (2).png", "a.png"])
}

@Test func collisionOnAFileWithNoExtension() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Other")
    try "original".write(to: dest.appendingPathComponent("README"), atomically: true, encoding: .utf8)
    let source = try temp.writeFile("README", contents: "incoming")

    let final = try FileMover().move(source, into: dest)
    #expect(final.lastPathComponent == "README (1)")
}

@Test func missingSourceThrowsAndChangesNothing() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let ghost = temp.url.appendingPathComponent("ghost.png")

    #expect(throws: MoveError.sourceMissing(ghost)) {
        try FileMover().move(ghost, into: dest)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: dest.path)
    #expect(names.isEmpty)
}

/// Thread-safe accumulator for results reported concurrently from
/// `DispatchQueue.concurrentPerform`, used only by the race test below.
private final class ConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Result<URL, Error>] = []

    func record(_ value: Result<URL, Error>) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func snapshot() -> [Result<URL, Error>] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

@Test func concurrentMovesToTheSameNameAllSucceedInsteadOfThrowing() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let count = 8

    // A deliberately slow rename. The window this lock exists to close is
    // between `availableURL` choosing a free name and the rename landing on
    // it; left to the scheduler that window is microseconds wide, and an
    // earlier audit measured this test catching a removed lock only 11 runs in
    // 12 — a green run was not evidence the lock was there. Widening the
    // window to 20ms makes the race a certainty instead of an accident: with
    // the lock, movers queue up and the pause costs nothing; without it, all
    // eight choose the same name before any of them acts on it.
    let mover = FileMover { from, to in
        Thread.sleep(forTimeInterval: 0.02)
        try FileManager.default.moveItem(at: from, to: to)
    }

    // Distinct source files that all happen to be named "a.png", so every
    // concurrent mover races `availableURL`/`moveItem` over the same
    // destination name — this is the folder watcher and Organize Now
    // colliding on the same download in practice.
    let sources = try (0..<count).map { try temp.writeFile("src\($0)/a.png") }

    // Real threads released from a barrier, not `concurrentPerform`: GCD caps
    // concurrent iterations at the core count, and with fewer than seven
    // movers genuinely overlapping the retry budget can absorb the collisions
    // and hide a missing lock. Blocked threads cost nothing, so this overlaps
    // all eight on any machine.
    let results = ConcurrentResults()
    let ready = DispatchSemaphore(value: 0)
    let go = DispatchSemaphore(value: 0)
    let done = DispatchGroup()

    for index in 0..<count {
        done.enter()
        let thread = Thread {
            ready.signal()
            go.wait()
            do {
                results.record(.success(try mover.move(sources[index], into: dest)))
            } catch {
                results.record(.failure(error))
            }
            done.leave()
        }
        thread.start()
    }
    for _ in 0..<count { ready.wait() }
    for _ in 0..<count { go.signal() }
    done.wait()

    let outcomes = results.snapshot()
    let failures = outcomes.compactMap { outcome -> Error? in
        if case .failure(let error) = outcome { return error }
        return nil
    }
    #expect(failures.isEmpty, "a lost collision race must retry, not throw: \(failures)")

    // Every mover landed on a distinct, correctly-numbered name — no file
    // was clobbered and none was silently dropped.
    let names = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
    let expected = (["a.png"] + (1..<count).map { "a (\($0)).png" }).sorted()
    #expect(names == expected)
}

/// Counts how many times the mover attempted a rename, so the retry loop's
/// behaviour is observable rather than inferred.
private final class AttemptCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}

private func cocoaError(_ code: CocoaError.Code) -> NSError {
    NSError(domain: NSCocoaErrorDomain, code: code.rawValue)
}

/// The retry loop guards a collision arriving from *outside* this process —
/// Finder, or another app, claiming the name in the window between
/// `availableURL` and the rename. The in-process lock means no caller here can
/// ever produce one, so the rename is stood in for: fail the first attempt the
/// way a lost race fails, and leave the racer's file behind so the retry finds
/// the name genuinely taken.
@Test func aNameLostToAnOutsideProcessIsRetriedOntoTheNextFreeName() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let source = try temp.writeFile("a.png", contents: "incoming")

    let attempts = AttemptCounter()
    let mover = FileMover { from, to in
        if attempts.next() == 1 {
            try "outsider".write(to: to, atomically: true, encoding: .utf8)
            throw cocoaError(.fileWriteFileExists)
        }
        try FileManager.default.moveItem(at: from, to: to)
    }

    let final = try mover.move(source, into: dest)

    #expect(attempts.count == 2, "a lost name race must be retried, not surfaced to the caller")
    #expect(final.lastPathComponent == "a (1).png")
    #expect(try String(contentsOf: dest.appendingPathComponent("a.png"), encoding: .utf8) == "outsider",
            "the file the racer left must not be clobbered by the retry")
    #expect(try String(contentsOf: final, encoding: .utf8) == "incoming")
}

@Test func aCollisionThatNeverClearsGivesUpAfterTheRetryBudget() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let source = try temp.writeFile("a.png")

    let attempts = AttemptCounter()
    let mover = FileMover { _, _ in
        attempts.next()
        throw cocoaError(.fileWriteFileExists)
    }

    #expect(throws: MoveError.underlying(domain: NSCocoaErrorDomain,
                                         code: CocoaError.fileWriteFileExists.rawValue,
                                         description: "")) {
        try mover.move(source, into: dest)
    }
    #expect(attempts.count == FileMover.maxCollisionRetries + 1,
            "the retry is bounded: one attempt plus the budget, never a spin")
    #expect(FileManager.default.fileExists(atPath: source.path),
            "a move that gave up must leave the source where it was")
}

@Test func aFailureThatIsNotACollisionIsSurfacedWithoutRetrying() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let source = try temp.writeFile("a.png")

    let attempts = AttemptCounter()
    let mover = FileMover { _, _ in
        attempts.next()
        throw cocoaError(.fileWriteOutOfSpace)
    }

    #expect(throws: MoveError.underlying(domain: NSCocoaErrorDomain,
                                         code: CocoaError.fileWriteOutOfSpace.rawValue,
                                         description: "")) {
        try mover.move(source, into: dest)
    }
    #expect(attempts.count == 1, "a full disk is not fixed by asking again five more times")
}

/// The pure predicate behind the loop above. A retry is only ever right for one
/// error; broadening it turns an unfixable failure into six doomed attempts and
/// buries the real reason.
@Test(arguments: [
    (NSCocoaErrorDomain, CocoaError.fileWriteFileExists.rawValue, true),
    (NSCocoaErrorDomain, CocoaError.fileWriteOutOfSpace.rawValue, false),
    (NSCocoaErrorDomain, CocoaError.fileWriteNoPermission.rawValue, false),
    (NSCocoaErrorDomain, CocoaError.fileNoSuchFile.rawValue, false),
    (NSPOSIXErrorDomain, Int(EEXIST), false)
])
func isNameCollisionMatchesOnlyTheClobberRefusal(domain: String, code: Int, expected: Bool) {
    #expect(FileMover.isNameCollision(NSError(domain: domain, code: code)) == expected)
}

@Test func anUnwritableDestinationThrowsDestinationNotWritable() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png")
    // A *file* standing where the destination folder should be, so
    // `createDirectory` cannot succeed. The specific error matters: the UI has
    // to be able to say "that folder isn't writable" rather than relay a raw
    // Cocoa code from a rename that was never attempted.
    let blocker = try temp.writeFile("Images")

    #expect(throws: MoveError.destinationNotWritable(blocker)) {
        try FileMover().move(source, into: blocker)
    }
    #expect(FileManager.default.fileExists(atPath: source.path),
            "a failed move must leave the source alone")
}

@Test func movesADirectoryAsASingleUnit() throws {
    let temp = try TempDirectory()
    let project = try temp.makeDirectory("Project.app")
    try "x".write(to: project.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
    let dest = temp.url.appendingPathComponent("Apps", isDirectory: true)

    let final = try FileMover().move(project, into: dest)

    #expect(final == dest.appendingPathComponent("Project.app"))
    #expect(FileManager.default.fileExists(atPath: final.appendingPathComponent("inner.txt").path))
}

// MARK: - Dangling symlinks
//
// `FileManager.fileExists` resolves symlinks and so reports `false` for a link
// whose target is gone, while `moveItem` still refuses to write over the link
// itself. That disagreement used to make an occupied name look free: the move
// was rejected with `fileWriteFileExists`, the retry recomputed the identical
// name, and the item stayed unfileable for good. Organize Now made it worse by
// showing the user that name in a preview first.

@Test func aDanglingSymlinkStillOccupiesItsName() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Documents")
    try FileManager.default.createSymbolicLink(
        atPath: dest.appendingPathComponent("a.pdf").path,
        withDestinationPath: dest.appendingPathComponent("gone.pdf").path)

    // The premise: Foundation's own existence check disagrees with the move.
    #expect(!FileManager.default.fileExists(atPath: dest.appendingPathComponent("a.pdf").path),
            "premise: fileExists resolves the link and calls the name free")

    #expect(FileMover.availableURL(for: "a.pdf", in: dest).lastPathComponent == "a (1).pdf")
}

@Test func movingOntoADanglingSymlinkSucceedsAndLeavesTheLinkAlone() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Documents")
    let link = dest.appendingPathComponent("a.pdf")
    try FileManager.default.createSymbolicLink(
        atPath: link.path, withDestinationPath: dest.appendingPathComponent("gone.pdf").path)
    let source = try temp.writeFile("a.pdf", contents: "incoming")

    let final = try FileMover().move(source, into: dest)

    #expect(final.lastPathComponent == "a (1).pdf")
    #expect(try String(contentsOf: final, encoding: .utf8) == "incoming")

    // The link is the user's file too. Never overwritten — the same promise
    // this type makes about everything else in its way.
    var info = stat()
    #expect(lstat(link.path, &info) == 0, "the dangling link must survive the move")
}

@Test func aLiveSymlinkIsNotFollowedAndItsTargetIsNotWrittenThrough() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Documents")
    let target = try temp.writeFile("real.pdf", contents: "target")
    try FileManager.default.createSymbolicLink(
        atPath: dest.appendingPathComponent("a.pdf").path, withDestinationPath: target.path)
    let source = try temp.writeFile("nested/a.pdf", contents: "incoming")

    let final = try FileMover().move(source, into: dest)

    #expect(final.lastPathComponent == "a (1).pdf")
    #expect(try String(contentsOf: target, encoding: .utf8) == "target")
}
