import Testing
import Foundation
@testable import LedgeCore

// The Settings pane lets the user rename a project in place. A name is what the
// destination menu shows, so "" and "   " must not become what they see.

@Test func renamingKeepsTheIdentityAndTheFolder() {
    let project = Project(name: "Alpha", folder: URL(fileURLWithPath: "/tmp/Alpha"))
    let renamed = project.renamed(to: "Q3 launch")

    #expect(renamed.name == "Q3 launch")
    #expect(renamed.id == project.id)
    #expect(renamed.folder == project.folder)
}

@Test func renamingTrimsSurroundingWhitespace() {
    let project = Project(name: "Alpha", folder: URL(fileURLWithPath: "/tmp/Alpha"))

    #expect(project.renamed(to: "  Q3 launch \n").name == "Q3 launch")
}

@Test func renamingToBlankFallsBackToTheFolderName() {
    let project = Project(name: "Alpha", folder: URL(fileURLWithPath: "/tmp/Downloads Archive"))

    #expect(project.renamed(to: "").name == "Downloads Archive")
    #expect(project.renamed(to: "   ").name == "Downloads Archive")
    #expect(project.renamed(to: "\t\n").name == "Downloads Archive")
}

/// Whitespace is trimmed, not stripped — a name is allowed to contain spaces.
@Test func renamingKeepsInteriorSpaces() {
    let project = Project(name: "Alpha", folder: URL(fileURLWithPath: "/tmp/Alpha"))

    #expect(project.renamed(to: "Client work  2026").name == "Client work  2026")
}
