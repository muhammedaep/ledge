import Testing
import Foundation
@testable import LedgeCore

// Project identity is the folder, not the id. `Project(folder:)` mints a fresh
// UUID every call, so a shelf that appended unconditionally produced two
// identical menu entries pointing at the same place. These pin the rule that
// replaced that.

@Test func choosingANewFolderAppendsIt() {
    let folder = URL(fileURLWithPath: "/tmp/Summit 2026", isDirectory: true)
    let choice = Project.choosing(folder, in: [])

    #expect(choice.wasAlreadyKnown == false)
    #expect(choice.projects.count == 1)
    #expect(choice.projects.first == choice.project)
    #expect(choice.project.name == "Summit 2026")
}

@Test func choosingTheSameFolderTwiceDoesNotGrowTheList() {
    let folder = URL(fileURLWithPath: "/tmp/Summit 2026", isDirectory: true)
    let first = Project.choosing(folder, in: [])
    let second = Project.choosing(folder, in: first.projects)

    #expect(second.wasAlreadyKnown == true)
    #expect(second.projects.count == 1)
    #expect(second.projects == first.projects)
}

/// The point of returning the existing project rather than a fresh one: the
/// caller activates this id, and `AppState.updateProjects` clears the active
/// project when its id is absent from the list. A freshly minted duplicate id
/// would either be a phantom or an accumulating duplicate.
@Test func choosingAKnownFolderReturnsTheExistingProjectNotACopy() {
    let folder = URL(fileURLWithPath: "/tmp/Summit 2026", isDirectory: true)
    let existing = Project(name: "Renamed by the user", folder: folder)

    let choice = Project.choosing(folder, in: [existing])

    #expect(choice.project.id == existing.id)
    #expect(choice.project.name == "Renamed by the user")
    #expect(choice.projects.map(\.id) == [existing.id])
}

@Test func differentFoldersAreDifferentProjects() {
    let first = Project.choosing(URL(fileURLWithPath: "/tmp/Alpha", isDirectory: true), in: [])
    let second = Project.choosing(URL(fileURLWithPath: "/tmp/Beta", isDirectory: true),
                                  in: first.projects)

    #expect(second.wasAlreadyKnown == false)
    #expect(second.projects.count == 2)
}

@Test func aTrailingSlashIsTheSameFolder() {
    let existing = Project(folder: URL(fileURLWithPath: "/tmp/Summit", isDirectory: true))
    let withSlash = URL(fileURLWithPath: "/tmp/Summit/", isDirectory: true)

    #expect(Project.choosing(withSlash, in: [existing]).wasAlreadyKnown == true)
}

@Test func aRelativeComponentIsTheSameFolder() {
    let existing = Project(folder: URL(fileURLWithPath: "/tmp/Summit", isDirectory: true))
    let roundabout = URL(fileURLWithPath: "/tmp/Archive/../Summit", isDirectory: true)

    #expect(Project.choosing(roundabout, in: [existing]).wasAlreadyKnown == true)
}

/// The case that motivated resolving symlinks rather than just standardizing:
/// on macOS `/tmp` is a symlink to `/private/tmp`, and an open panel can hand
/// back either form for the same directory.
@Test func aSymlinkedPathIsTheSameFolder() throws {
    let temp = try TempDirectory()
    let real = try temp.makeDirectory("Real Project")
    let link = temp.url.appendingPathComponent("Link To Project", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

    let existing = Project(folder: real)

    #expect(Project.choosing(link, in: [existing]).wasAlreadyKnown == true)
}

/// A project on an unmounted volume, or one whose folder the user deleted, is
/// still that project — it must not silently duplicate while it is away.
@Test func aFolderThatNoLongerExistsStillMatchesItself() throws {
    let temp = try TempDirectory()
    let folder = try temp.makeDirectory("Gone")
    let existing = Project(folder: folder)
    try FileManager.default.removeItem(at: folder)

    let choice = Project.choosing(folder, in: [existing])

    #expect(choice.wasAlreadyKnown == true)
    #expect(choice.projects.count == 1)
}
