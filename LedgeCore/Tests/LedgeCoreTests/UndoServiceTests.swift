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
