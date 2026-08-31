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
    try MoveJournal(directory: temp.url).append(record("a.png"))
    #expect(MoveJournal(directory: temp.url).records.count == 1)
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

@Test func batchRecordsAreGroupedAndRemovedTogether() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let batch = UUID()

    try journal.append(record("a.png", batchID: batch))
    try journal.append(record("b.png", batchID: batch))
    try journal.append(record("solo.png"))

    #expect(journal.records(inBatch: batch).count == 2)

    try journal.remove(batchID: batch)
    #expect(journal.records.map(\.originalName) == ["solo.png"])
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

@Test func removingByBatchIdPersistsAcrossReload() throws {
    let temp = try TempDirectory()
    let journal = MoveJournal(directory: temp.url)
    let batch = UUID()

    try journal.append(record("a.png", batchID: batch))
    try journal.append(record("b.png", batchID: batch))
    try journal.append(record("solo.png"))

    try journal.remove(batchID: batch)

    // A fresh instance over the same directory must not see the removed batch.
    #expect(MoveJournal(directory: temp.url).records.map(\.originalName) == ["solo.png"])
}

@Test func corruptJournalFileLoadsAsEmpty() throws {
    let temp = try TempDirectory()
    try temp.writeFile("journal.json", contents: "not valid json")

    #expect(MoveJournal(directory: temp.url).records.isEmpty)
}
