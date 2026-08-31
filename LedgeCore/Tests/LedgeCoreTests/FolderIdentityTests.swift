import Testing
import Foundation
@testable import LedgeCore

// Two questions that were being answered twice, differently: "are these the
// same folder" (projects collapsed the spellings, watched folders did not) and
// "can we use this folder" (a missing folder was reported as a denied one, which
// put the app in front of a permission dialog for a folder that is not there).

// MARK: - Identity

@Test func trailingSlashIsTheSameFolder() {
    #expect(FolderIdentity.sameFolder(
        URL(fileURLWithPath: "/private/tmp/ledge-x"),
        URL(fileURLWithPath: "/private/tmp/ledge-x/")))
}

@Test func aDotDotComponentIsTheSameFolder() {
    #expect(FolderIdentity.sameFolder(
        URL(fileURLWithPath: "/private/tmp/ledge-x"),
        URL(fileURLWithPath: "/private/tmp/sibling/../ledge-x")))
}

/// `/tmp` is a symlink to `/private/tmp` on macOS, and an open panel can hand
/// back either spelling — this is the case that actually bites in the field.
@Test func aSymlinkedParentIsTheSameFolder() {
    #expect(FolderIdentity.sameFolder(
        URL(fileURLWithPath: "/tmp"),
        URL(fileURLWithPath: "/private/tmp")))
}

@Test func differentFoldersAreNotTheSame() {
    #expect(!FolderIdentity.sameFolder(
        URL(fileURLWithPath: "/private/tmp/ledge-a"),
        URL(fileURLWithPath: "/private/tmp/ledge-b")))
}

/// A folder that has gone (deleted, or on an unmounted volume) still has to
/// compare equal to itself, or it would be silently duplicated while away.
@Test func aFolderThatDoesNotExistStillMatchesItself() {
    let gone = URL(fileURLWithPath: "/private/tmp/ledge-not-here-\(UUID().uuidString)")
    #expect(FolderIdentity.sameFolder(gone, gone))
    #expect(FolderIdentity.contains([gone], gone))
}

/// Creates a real directory under `/tmp` and hands back both spellings of it.
/// They have to exist: `resolvingSymlinksInPath()` only resolves a path the
/// filesystem can actually walk — see `symlinkCollapsingNeedsThePathToExist`.
private func makeTwoSpellings() throws -> (short: URL, resolved: URL, cleanup: () -> Void) {
    let name = "ledge-identity-\(UUID().uuidString)"
    let short = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
    try FileManager.default.createDirectory(at: short, withIntermediateDirectories: true)
    return (
        short,
        URL(fileURLWithPath: "/private/tmp").appendingPathComponent(name),
        { try? FileManager.default.removeItem(at: short) }
    )
}

@Test func containsMatchesAcrossSpellings() throws {
    let (short, resolved, cleanup) = try makeTwoSpellings()
    defer { cleanup() }

    #expect(FolderIdentity.contains([resolved], short))
    #expect(FolderIdentity.contains([resolved], short.appendingPathComponent("")))
    #expect(!FolderIdentity.contains([resolved], URL(fileURLWithPath: "/tmp/ledge-elsewhere")))
}

@Test func addingTheSameFolderTwiceDoesNotGrowTheList() throws {
    let (short, resolved, cleanup) = try makeTwoSpellings()
    defer { cleanup() }

    let first = FolderIdentity.adding(short, to: [])
    let second = FolderIdentity.adding(resolved, to: first)

    #expect(first.count == 1)
    #expect(second == first)
}

@Test func removingMatchesAcrossSpellings() throws {
    let (short, resolved, cleanup) = try makeTwoSpellings()
    defer { cleanup() }

    let other = URL(fileURLWithPath: "/private/tmp/ledge-keep-me")
    let left = FolderIdentity.removing(short, from: [resolved, other])

    #expect(left == [other])
}

/// The limit of the rule, pinned deliberately rather than assumed away.
///
/// `resolvingSymlinksInPath()` leaves a path it cannot walk exactly as it found
/// it — it does not resolve the existing prefix — so two spellings of a folder
/// that is *gone* do not compare equal. That is survivable because of where the
/// spellings come from: an open panel can only return a folder that exists, so
/// every entry is resolved at the moment it is added, and comparisons between
/// stored entries are then already in the same form.
@Test func symlinkCollapsingNeedsThePathToExist() {
    let name = "ledge-never-created-\(UUID().uuidString)"
    let short = URL(fileURLWithPath: "/tmp").appendingPathComponent(name)
    let resolved = URL(fileURLWithPath: "/private/tmp").appendingPathComponent(name)

    #expect(!FolderIdentity.sameFolder(short, resolved))
    #expect(FolderIdentity.sameFolder(short, short.appendingPathComponent("")))
}

// MARK: - Access

@Test func anOrdinaryFolderIsReadable() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ledge-access-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    #expect(FolderAccess.of(folder) == .readable)
}

@Test func aFolderThatIsNotThereIsMissingRatherThanUnreadable() {
    let gone = FileManager.default.temporaryDirectory
        .appendingPathComponent("ledge-gone-\(UUID().uuidString)")

    #expect(FolderAccess.of(gone) == .missing)
}

/// The distinction this type exists for. An ejected drive and a declined
/// consent prompt both stop filing, but only one of them is something the user
/// can grant — offering Privacy Settings for the other is a dead end.
@Test func aFolderWhoseContentsCannotBeListedIsUnreadable() throws {
    let folder = FileManager.default.temporaryDirectory
        .appendingPathComponent("ledge-denied-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        try? FileManager.default.removeItem(at: folder)
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)

    #expect(FolderAccess.of(folder) == .unreadable)
}

/// A file is not a folder, and must not read as a usable one.
@Test func aPlainFileIsMissingRatherThanReadable() throws {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("ledge-file-\(UUID().uuidString).txt")
    try Data("x".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }

    #expect(FolderAccess.of(file) == .missing)
}
