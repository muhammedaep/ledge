import Testing
import Foundation
@testable import LedgeCore

@Test func projectNameDefaultsToFolderName() {
    let project = Project(folder: URL(fileURLWithPath: "/tmp/Summit 2026", isDirectory: true))
    #expect(project.name == "Summit 2026")
}

@Test func projectNameCanBeOverridden() {
    let project = Project(name: "Client work",
                          folder: URL(fileURLWithPath: "/tmp/Summit 2026", isDirectory: true))
    #expect(project.name == "Client work")
}

@Test func loadReturnsEmptyWhenNoFileExists() throws {
    let temp = try TempDirectory()
    #expect(ProjectStore(directory: temp.url).load().isEmpty)
}

@Test func savedProjectsAreLoadedBack() throws {
    let temp = try TempDirectory()
    let store = ProjectStore(directory: temp.url)
    let projects = [
        Project(folder: URL(fileURLWithPath: "/tmp/Summit 2026", isDirectory: true)),
        Project(name: "IFL", folder: URL(fileURLWithPath: "/tmp/ifl", isDirectory: true))
    ]

    try store.save(projects)
    #expect(ProjectStore(directory: temp.url).load() == projects)
}

@Test func orderIsPreservedAcrossReload() throws {
    let temp = try TempDirectory()
    let store = ProjectStore(directory: temp.url)
    let projects = (0..<5).map {
        Project(folder: URL(fileURLWithPath: "/tmp/p\($0)", isDirectory: true))
    }

    try store.save(projects)
    #expect(ProjectStore(directory: temp.url).load().map(\.name) == projects.map(\.name))
}

@Test func aCorruptFileDegradesToEmptyRatherThanCrashing() throws {
    let temp = try TempDirectory()
    try "{ not json".write(to: temp.url.appendingPathComponent("projects.json"),
                           atomically: true, encoding: .utf8)
    #expect(ProjectStore(directory: temp.url).load().isEmpty)
}

@Test func projectStoreSaveCreatesTheDirectoryIfMissing() throws {
    let temp = try TempDirectory()
    let nested = temp.url.appendingPathComponent("Ledge", isDirectory: true)
    try ProjectStore(directory: nested).save([
        Project(folder: URL(fileURLWithPath: "/tmp/p", isDirectory: true))
    ])
    #expect(FileManager.default.fileExists(
        atPath: nested.appendingPathComponent("projects.json").path))
}
