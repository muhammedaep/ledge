import Testing
import Foundation
@testable import LedgeCore

@Test func movesFileIntoDestination() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png")
    let dest = temp.url.appendingPathComponent("Images", isDirectory: true)

    let final = try FileMover().move(source, into: dest)

    #expect(final == dest.appendingPathComponent("a.png"))
    #expect(FileManager.default.fileExists(atPath: final.path))
    #expect(!FileManager.default.fileExists(atPath: source.path))
}

@Test func createsDestinationFolderWhenMissing() throws {
    let temp = try TempDirectory()
    let source = try temp.writeFile("a.png")
    let dest = temp.url.appendingPathComponent("Images/PNG", isDirectory: true)

    let final = try FileMover().move(source, into: dest)
    #expect(FileManager.default.fileExists(atPath: final.path))
}

@Test func neverOverwritesAnExistingFile() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    try "original".write(to: dest.appendingPathComponent("a.png"), atomically: true, encoding: .utf8)
    let source = try temp.writeFile("a.png", contents: "incoming")

    let final = try FileMover().move(source, into: dest)

    #expect(final.lastPathComponent == "a (1).png")
    let untouched = try String(contentsOf: dest.appendingPathComponent("a.png"), encoding: .utf8)
    #expect(untouched == "original")
    #expect(try String(contentsOf: final, encoding: .utf8) == "incoming")
}

@Test func collisionCounterKeepsClimbing() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let mover = FileMover()

    for _ in 0..<3 {
        let source = try temp.writeFile("a.png")
        _ = try mover.move(source, into: dest)
    }

    let names = try FileManager.default.contentsOfDirectory(atPath: dest.path).sorted()
    #expect(names == ["a (1).png", "a (2).png", "a.png"])
}

@Test func collisionOnAFileWithNoExtension() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Other")
    try "original".write(to: dest.appendingPathComponent("README"), atomically: true, encoding: .utf8)
    let source = try temp.writeFile("README", contents: "incoming")

    let final = try FileMover().move(source, into: dest)
    #expect(final.lastPathComponent == "README (1)")
}

@Test func missingSourceThrowsAndChangesNothing() throws {
    let temp = try TempDirectory()
    let dest = try temp.makeDirectory("Images")
    let ghost = temp.url.appendingPathComponent("ghost.png")

    #expect(throws: MoveError.sourceMissing(ghost)) {
        try FileMover().move(ghost, into: dest)
    }
    let names = try FileManager.default.contentsOfDirectory(atPath: dest.path)
    #expect(names.isEmpty)
}

@Test func movesADirectoryAsASingleUnit() throws {
    let temp = try TempDirectory()
    let project = try temp.makeDirectory("Project.app")
    try "x".write(to: project.appendingPathComponent("inner.txt"), atomically: true, encoding: .utf8)
    let dest = temp.url.appendingPathComponent("Apps", isDirectory: true)

    let final = try FileMover().move(project, into: dest)

    #expect(final == dest.appendingPathComponent("Project.app"))
    #expect(FileManager.default.fileExists(atPath: final.appendingPathComponent("inner.txt").path))
}
