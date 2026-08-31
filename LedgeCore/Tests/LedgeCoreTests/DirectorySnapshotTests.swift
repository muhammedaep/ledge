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

/// The seam the rest of this file leaves open: the diff tests above use
/// hand-built fixtures and the scan tests compare only `lastPathComponent`, so
/// nothing else ever diffs two *real* scans — which is the single thing this
/// type exists to do. Whole URLs, deliberately, not names.
@Test func newEntriesFromTwoRealScansOfTheSameFolder() throws {
    let temp = try TempDirectory()
    try temp.writeFile("already-here.png")

    let before = DirectorySnapshot(scanning: temp.url)
    let added = try temp.writeFile("new.png")
    let after = DirectorySnapshot(scanning: temp.url)

    #expect(after.newEntries(comparedTo: before) == [added.resolvingSymlinksInPath()])
    #expect(before.newEntries(comparedTo: after).isEmpty)
}

/// `entries` is a `Set<URL>` and `URL` equality is path-string equality, so an
/// entry has to come back spelled the same way a caller would spell it. It does
/// not by default: handed a folder under `/var/…`, `contentsOfDirectory` returns
/// its contents under `/private/var/…` — the same files, a different key in
/// every set they are put into.
@Test func scanEntriesMatchURLsBuiltFromTheFolderThatWasScanned() throws {
    let temp = try TempDirectory()
    try temp.writeFile("top.png")
    try temp.writeFile("second.png")

    let entries = DirectorySnapshot(scanning: temp.url).entries
    let expected = Set(["top.png", "second.png"].map {
        temp.url.appendingPathComponent($0).resolvingSymlinksInPath()
    })

    #expect(entries == expected, "a scan must be comparable to URLs constructed elsewhere")
}

@Test func scanningAMissingFolderYieldsNothing() {
    let snapshot = DirectorySnapshot(scanning: URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID())"))
    #expect(snapshot.entries.isEmpty)
}
