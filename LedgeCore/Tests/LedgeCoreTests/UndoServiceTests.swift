import Testing
import Foundation
@testable import LedgeCore

@Test func undoReturnsFileToItsOriginalFolder() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png")
    let dest = temp.url.appendingPathComponent("Images", isDirectory: true)
    let mover = FileMover()
    let journal = MoveJournal(directory: temp.url)

    let moved = try mover.move(source, into: dest)
    let record = MoveRecord(originalName: "a.png", from: temp.url, to: moved)
    try journal.append(record)

    let restored = try UndoService(mover: mover, journal: journal).undo(record)

    #expect(restored == temp.url.appendingPathComponent("a.png"))
    #expect(FileManager.default.fileExists(atPath: restored.path))
    #expect(!FileManager.default.fileExists(atPath: moved.path))
    #expect(journal.records.isEmpty)
}

@Test func undoDoesNotOverwriteAFileThatReappearedAtTheOriginalPath() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png", contents: "first")
    let dest = temp.url.appendingPathComponent("Images", isDirectory: true)
    let mover = FileMover()
    let journal = MoveJournal(directory: temp.url)

    let moved = try mover.move(source, into: dest)
    let record = MoveRecord(originalName: "a.png", from: temp.url, to: moved)
    try journal.append(record)

    // A new download with the same name arrived while the file was filed away.
    try temp.writeFile("a.png", contents: "second")

    let restored = try UndoService(mover: mover, journal: journal).undo(record)

    #expect(restored.lastPathComponent == "a (1).png")
    #expect(try String(contentsOf: temp.url.appendingPathComponent("a.png"), encoding: .utf8) == "second")
}

@Test func undoFailsWhenTheFileIsGoneFromTheRecordedPath() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let ghost = temp.url.appendingPathComponent("Images/a.png")
    let record = MoveRecord(originalName: "a.png", from: temp.url, to: ghost)
    try journal.append(record)

    #expect(throws: UndoError.fileNoLongerAtRecordedPath(ghost)) {
        try UndoService(mover: FileMover(), journal: journal).undo(record)
    }
    #expect(journal.records.count == 1, "a failed undo must not drop the record")
}

@Test func undoBatchRestoresEveryFileAndClearsTheBatch() throws {
    let temp = try TempDirectory()
    let mover = FileMover()
    let journal = MoveJournal(directory: temp.url)
    let batch = UUID()
    let dest = temp.url.appendingPathComponent("Images", isDirectory: true)

    for name in ["a.png", "b.png"] {
        let moved = try mover.move(try temp.writeFile(name), into: dest)
        try journal.append(MoveRecord(originalName: name, from: temp.url, to: moved, batchID: batch))
    }

    let restored = try UndoService(mover: mover, journal: journal).undoBatch(batch)

    #expect(restored.count == 2)
    #expect(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("a.png").path))
    #expect(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("b.png").path))
    #expect(journal.records.isEmpty)
}

@Test func undoBatchKeepsTheJournalRecordForAFileItCouldNotRestore() throws {
    let temp = try TempDirectory()
    let mover = FileMover()
    let journal = MoveJournal(directory: temp.url)
    let batch = UUID()
    let dest = temp.url.appendingPathComponent("Images", isDirectory: true)

    var records: [MoveRecord] = []
    for name in ["a.png", "b.png", "c.png"] {
        let moved = try mover.move(try temp.writeFile(name), into: dest)
        let record = MoveRecord(originalName: name, from: temp.url, to: moved, batchID: batch)
        try journal.append(record)
        records.append(record)
    }

    // "c.png" is gone from its recorded path before undo runs -- restored
    // from Trash to somewhere else, resynced by iCloud/Dropbox, whatever the
    // cause. undoBatch must skip it, not lose track of it.
    let missing = records[2]
    try FileManager.default.removeItem(at: missing.to)

    let restored = try UndoService(mover: mover, journal: journal).undoBatch(batch)

    #expect(restored.count == 2)
    #expect(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("a.png").path))
    #expect(FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("b.png").path))

    let remaining = journal.records(inBatch: batch)
    #expect(remaining.map(\.id) == [missing.id], "the skipped file's record must survive so it stays individually undoable")
    #expect(journal.records.count == 1)
}

/// A record whose file is a dangling symlink describes a file that is still
/// there. `fileExists` resolves the link and says otherwise, so undo refused a
/// move `FileMover` performs happily — and the user's only route back was to
/// delete the link by hand.
@Test func undoRestoresARecordWhoseFileIsADanglingSymlink() throws {
    let temp = try TempDirectory()
    let link = try temp.makeSymlink("Documents/report.pdf", to: "/nonexistent/target")
    let journal = MoveJournal(directory: temp.url)
    let record = MoveRecord(originalName: "report.pdf", from: temp.url, to: link)
    try journal.append(record)

    let restored = try UndoService(mover: FileMover(), journal: journal).undo(record)

    #expect(restored == temp.url.appendingPathComponent("report.pdf"))
    var info = stat()
    #expect(lstat(restored.path, &info) == 0)
    #expect(journal.records.isEmpty)
}

/// The batch case, which fails differently and worse. `undoBatch` skips a
/// record it believes is gone, so a dangling link was silently left behind
/// while every other record in the batch was restored.
@Test func undoBatchRestoresADanglingSymlinkAlongsideTheRest() throws {
    let temp = try TempDirectory()
    let mover = FileMover()
    let journal = MoveJournal(directory: temp.url)
    let batch = UUID()
    let dest = temp.url.appendingPathComponent("Documents", isDirectory: true)

    let moved = try mover.move(try temp.writeFile("a.pdf"), into: dest)
    try journal.append(MoveRecord(originalName: "a.pdf", from: temp.url, to: moved, batchID: batch))

    let link = try temp.makeSymlink("Documents/b.pdf", to: "/nonexistent/target")
    try journal.append(MoveRecord(originalName: "b.pdf", from: temp.url, to: link, batchID: batch))

    let restored = try UndoService(mover: mover, journal: journal).undoBatch(batch)

    #expect(restored.count == 2)
    var info = stat()
    #expect(lstat(temp.url.appendingPathComponent("b.pdf").path, &info) == 0,
            "the link belongs back where it came from, like every other record")
    #expect(journal.records.isEmpty, "nothing was skipped, so nothing is left behind")
}
