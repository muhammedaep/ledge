import Testing
import Foundation
@testable import LedgeCore

private func record(_ name: String, batch: UUID? = nil, at date: Date = Date()) -> MoveRecord {
    MoveRecord(originalName: name,
               from: URL(fileURLWithPath: "/tmp", isDirectory: true),
               to: URL(fileURLWithPath: "/tmp/Documents/\(name)"),
               date: date,
               batchID: batch)
}

@Test func anEmptyShelfHasNothingToUndo() {
    #expect(UndoTarget.mostRecent(in: []) == .nothing)
}

@Test func theMostRecentAutomaticMoveIsUndoneOnItsOwn() {
    let newest = record("a.pdf")
    #expect(UndoTarget.mostRecent(in: [newest, record("b.pdf")]) == .record(newest))
}

/// The half of spec §7.5 that is easy to drop: a batch undoes whole.
@Test func aBatchRecordUndoesTheWholeBatch() {
    let batch = UUID()
    let target = UndoTarget.mostRecent(in: [record("a.pdf", batch: batch), record("b.pdf")])
    #expect(target == .batch(batch))
}

/// Every record of one Organize Now pass carries the same `batchID`, so which
/// of them happens to be newest must not change the answer.
@Test func anyRecordOfTheBatchGivesTheSameBatch() {
    let batch = UUID()
    let first = UndoTarget.mostRecent(in: [record("a.pdf", batch: batch), record("b.pdf", batch: batch)])
    let second = UndoTarget.mostRecent(in: [record("b.pdf", batch: batch), record("a.pdf", batch: batch)])
    #expect(first == .batch(batch))
    #expect(first == second)
}

/// A batch sitting *under* a newer automatic move must not be reached for. ⌘Z
/// undoes the last thing that happened, not the last batch that happened.
@Test func anAutomaticMoveAboveABatchIsWhatUndoActsOn() {
    let newest = record("new.pdf")
    let target = UndoTarget.mostRecent(in: [newest, record("old.pdf", batch: UUID())])
    #expect(target == .record(newest))
}

/// `mostRecent` reads `records.first`, so it is only correct while the journal
/// is newest-first. That is documented rather than enforced by a type, and a
/// journal that quietly became oldest-first would make undo act on the wrong end
/// of the history while every other test still passed. Pinned against a real
/// journal, not against the doc comment.
@Test func theJournalHandsBackNewestFirst() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let start = Date()

    try journal.append(record("older.pdf", at: start))
    try journal.append(record("newer.pdf", at: start.addingTimeInterval(60)))

    #expect(journal.records.first?.originalName == "newer.pdf")
    #expect(UndoTarget.mostRecent(in: journal.records)
            == .record(try #require(journal.records.first)))
}
