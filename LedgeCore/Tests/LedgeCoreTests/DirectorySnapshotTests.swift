import Testing
import Foundation
@testable import LedgeCore

@Test func newEntriesAreTheDifference() {
    let a = URL(fileURLWithPath: "/tmp/a")
    let b = URL(fileURLWithPath: "/tmp/b")
    let before = DirectorySnapshot(entries: [a])
    let after = DirectorySnapshot(entries: [a, b])

    #expect(after.newEntries(comparedTo: before) == [b])
}

@Test func removedEntriesAreNotReportedAsNew() {
    let a = URL(fileURLWithPath: "/tmp/a")
    let before = DirectorySnapshot(entries: [a, URL(fileURLWithPath: "/tmp/gone")])
    let after = DirectorySnapshot(entries: [a])

    #expect(after.newEntries(comparedTo: before).isEmpty)
}

@Test func scanningReadsTopLevelEntriesOnly() throws {
    let temp = try TempDirectory()
    try temp.writeFile("top.png")
    try temp.writeFile("nested/inner.png")

    let names = Set(DirectorySnapshot(scanning: temp.url).entries.map(\.lastPathComponent))
    #expect(names == ["top.png", "nested"])
}

@Test func scanningSkipsHiddenFiles() throws {
    let temp = try TempDirectory()
    try temp.writeFile("visible.png")
    try temp.writeFile(".DS_Store")

    let names = Set(DirectorySnapshot(scanning: temp.url).entries.map(\.lastPathComponent))
    #expect(names == ["visible.png"])
}

@Test func scanningAMissingFolderYieldsNothing() {
    let snapshot = DirectorySnapshot(scanning: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID())"))
    #expect(snapshot.entries.isEmpty)
}
