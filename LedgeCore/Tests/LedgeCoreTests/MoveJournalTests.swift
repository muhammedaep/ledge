import Testing
import Foundation
@testable import LedgeCore

private func record(_ name: String, batchID: UUID? = nil, date: Date = Date()) -> MoveRecord {
    MoveRecord(originalName: name,
               from: URL(fileURLWithPath: "/tmp/from"),
               to: URL(fileURLWithPath: "/tmp/to/\(name)"),
               date: date,
               batchID: batchID)
}

@Test func newJournalIsEmpty() throws {
    let temp = try TempDirectory()
    #expect(MoveJournal(directory: temp.url).records.isEmpty)
}

@Test func recordsComeBackNewestFirst() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)

    try journal.append(record("old.png", date: Date(timeIntervalSince1970: 100)))
    try journal.append(record("new.png", date: Date(timeIntervalSince1970: 200)))

    #expect(journal.records.map(\.originalName) == ["new.png", "old.png"])
}

@Test func journalSurvivesReload() throws {
    let temp = try TempDirectory()
    // Whole-record equality, not a count: `batchID` in particular is what
    // "quit the app, reopen it, undo the batch you just ran" depends on, and
    // nothing else in the suite watches it cross a restart.
    // A whole-second date: the journal encodes dates as ISO8601, which has
    // second resolution, so a `Date()` would not survive verbatim.
    let original = record("a.png", batchID: UUID(), date: Date(timeIntervalSince1970: 1_756_600_000))
    try MoveJournal(directory: temp.url).append(original)
    #expect(MoveJournal(directory: temp.url).records == [original])
}

@Test func anOutOfOrderJournalFileIsSortedOnLoad() throws {
    let temp = try TempDirectory()
    let older = record("old.png", date: Date(timeIntervalSince1970: 100))
    let newer = record("new.png", date: Date(timeIntervalSince1970: 200))

    // Written directly rather than through append(), because append() always
    // persists an already-sorted array — the load-path sort only ever matters
    // for a file this version did not write: a hand edit, or an older build.
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([older, newer])
        .write(to: temp.url.appendingPathComponent("journal.json"))

    #expect(MoveJournal(directory: temp.url).records.map(\.originalName) == ["new.png", "old.png"])
}

@Test func oldestRecordsAreTrimmedAtTheCap() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url, cap: 3)

    for i in 0..<5 {
        try journal.append(record("f\(i).png", date: Date(timeIntervalSince1970: Double(i))))
    }

    #expect(journal.records.count == 3)
    #expect(journal.records.map(\.originalName) == ["f4.png", "f3.png", "f2.png"])
}

@Test func removingByIdDropsOneRecord() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let target = record("a.png")
    try journal.append(target)
    try journal.append(record("b.png"))

    try journal.remove(id: target.id)

    #expect(journal.records.map(\.originalName) == ["b.png"])
}

@Test func recordsInBatchReturnsExactlyThatBatch() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let batch = UUID()

    try journal.append(record("a.png", batchID: batch))
    try journal.append(record("b.png", batchID: batch))
    try journal.append(record("solo.png"))

    let inBatch = journal.records(inBatch: batch)
    #expect(inBatch.count == 2)
    #expect(Set(inBatch.map(\.originalName)) == ["a.png", "b.png"])
    #expect(!inBatch.contains { $0.originalName == "solo.png" })
}

@Test func removingByIdPersistsAcrossReload() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let target = record("a.png")
    try journal.append(target)
    try journal.append(record("b.png"))

    try journal.remove(id: target.id)

    // A fresh instance over the same directory must not see the removed record.
    #expect(MoveJournal(directory: temp.url).records.map(\.originalName) == ["b.png"])
}

@Test func corruptJournalFileLoadsAsEmpty() throws {
    let temp = try TempDirectory()
    try temp.writeFile("journal.json", contents: "not valid json")

    #expect(MoveJournal(directory: temp.url).records.isEmpty)
}

/// The journal is a file in Application Support, and a record's paths are what
/// undo, drag-out and reveal act on. A `to` that is not even a file URL —
/// `https://…` decodes without complaint, and its `.path` is a filesystem path
/// — is dropped on load rather than trusted.
@Test func aRecordWhosePathsAreNotFileURLsIsDroppedOnLoad() throws {
    let temp = try TempDirectory()
    let good = MoveRecord(originalName: "a.png", from: temp.url,
                          to: temp.url.appendingPathComponent("Images/a.png"))
    let poisoned = MoveRecord(originalName: "kitten.png",
                              from: URL(string: "https://evil.example/drop/")!,
                              to: URL(string: "https://evil.example/etc/passwd")!)
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    try encoder.encode([good, poisoned]).write(to: temp.url.appendingPathComponent("journal.json"))

    let records = MoveJournal(directory: temp.url).records

    #expect(records.map(\.originalName) == ["a.png"])
}
