import Testing
import Foundation
@testable import LedgeCore

@Test func factsReadAPackageDirectoryFromDisk() throws {
    let temp = try TempDirectory()
    // `.app` is a package type every macOS install registers, so this is a
    // real directory the system reports as one opaque thing — no dependency on
    // which third-party apps happen to be installed on the test machine.
    let bundle = try temp.makeDirectory("Ice.app")

    let facts = try #require(FileFacts(url: bundle))
    #expect(facts.isDirectory)
    #expect(facts.isPackage, "an .app directory is a package; Categorizer routes on this")
}

@Test func factsReportABrowsableFolderAsNotAPackage() throws {
    let temp = try TempDirectory()
    let folder = try temp.makeDirectory("footage.mp4")

    let facts = try #require(FileFacts(url: folder))
    #expect(facts.isDirectory)
    #expect(!facts.isPackage, "a folder merely named like a file is not a package")
}

@Test func factsReportAPlainFileAsNeitherDirectoryNorPackage() throws {
    let temp = try TempDirectory()
    let file = try temp.writeFile("a.png")

    let facts = try #require(FileFacts(url: file))
    #expect(!facts.isDirectory)
    #expect(!facts.isPackage)
}

@Test func factsAreNilForSomethingThatIsNotThere() throws {
    let temp = try TempDirectory()
    #expect(FileFacts(url: temp.url.appendingPathComponent("ghost.png")) == nil)
}
