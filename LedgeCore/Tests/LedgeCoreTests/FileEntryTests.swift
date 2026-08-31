import Testing
import Foundation
@testable import LedgeCore

// The whole reason this type exists is that `exists` and `isDirectory` must
// disagree about a symlink. Each test below pins one half of that; a version
// built on `FileManager.fileExists` fails the dangling cases, and one built on
// `lstat` alone fails the live-symlink directory case.

@Test func anEntryIsThereForAPlainFile() throws {
    let temp = try TempDirectory()
    let file = try temp.writeFile("a.png")
    #expect(FileEntry.exists(atPath: file.path))
}

@Test func nothingIsThereForAPathThatWasNeverWritten() throws {
    let temp = try TempDirectory()
    #expect(!FileEntry.exists(atPath: temp.url.appendingPathComponent("ghost.png").path))
}

/// The case the whole type is for. `FileManager.fileExists` resolves the link
/// and answers false here, which is what made a filed download unreachable to
/// undo and its name unusable to the mover.
@Test func aDanglingSymlinkIsAnEntryThatIsThere() throws {
    let temp = try TempDirectory()
    let link = try temp.makeSymlink("report.pdf", to: "/nonexistent/target")

    #expect(FileEntry.exists(atPath: link.path))
    #expect(!FileManager.default.fileExists(atPath: link.path),
            "the disagreement this type exists to settle, pinned rather than assumed")
}

@Test func aLiveSymlinkIsAnEntryThatIsThere() throws {
    let temp = try TempDirectory()
    let target = try temp.writeFile("real.pdf")
    let link = try temp.makeSymlink("alias.pdf", to: target.path)
    #expect(FileEntry.exists(atPath: link.path))
}

@Test func aDirectoryIsADirectory() throws {
    let temp = try TempDirectory()
    let folder = try temp.makeDirectory("Images")
    #expect(FileEntry.isDirectory(atPath: folder.path))
}

@Test func aPlainFileIsNotADirectory() throws {
    let temp = try TempDirectory()
    let file = try temp.writeFile("a.png")
    #expect(!FileEntry.isDirectory(atPath: file.path))
}

/// `isDirectory` follows links on purpose: a symlink to a folder is a folder a
/// download can land in, and `AppState` uses this to decide whether the active
/// project still has somewhere to file into.
@Test func aSymlinkToADirectoryIsADirectory() throws {
    let temp = try TempDirectory()
    let folder = try temp.makeDirectory("Project")
    let link = try temp.makeSymlink("Current", to: folder.path)
    #expect(FileEntry.isDirectory(atPath: link.path))
}

/// And the pair's asymmetry, in one place: a dangling link is an entry that is
/// there, and is not a directory. Anything answering both the same way has
/// collapsed the two questions back together.
@Test func aDanglingSymlinkIsPresentButIsNotADirectory() throws {
    let temp = try TempDirectory()
    let link = try temp.makeSymlink("Current", to: "/nonexistent/target")

    #expect(FileEntry.exists(atPath: link.path))
    #expect(!FileEntry.isDirectory(atPath: link.path))
}

@Test func anAbsentPathIsNotADirectory() throws {
    let temp = try TempDirectory()
    #expect(!FileEntry.isDirectory(atPath: temp.url.appendingPathComponent("ghost").path))
}
