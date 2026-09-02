import Testing
import Foundation
@testable import LedgeCore

private let rules = RuleSet(categories: [
    Category(name: "Images", extensions: ["png"]),
    Category(name: "Videos", extensions: ["mp4"]),
    Category(name: "Apps", extensions: ["app"])
])

@Test func plansOneMovePerLooseFile() throws {
    let temp = try TempDirectory()
    try temp.writeFile("a.png")
    try temp.writeFile("b.mp4")

    let plan = ScanEngine.plan(folder: temp.url, using: rules)

    #expect(plan.count == 2)
    #expect(Set(plan.map(\.destination.category)) == ["Images", "Videos"])
}

@Test func skipsHiddenFiles() throws {
    let temp = try TempDirectory()
    try temp.writeFile(".DS_Store")
    try temp.writeFile("a.png")

    #expect(ScanEngine.plan(folder: temp.url, using: rules).count == 1)
}

@Test func skipsFoldersThatAreAlreadyCategoryDestinations() throws {
    let temp = try TempDirectory()
    try temp.makeDirectory("Images")
    try temp.makeDirectory("Other")
    try temp.writeFile("a.png")

    let plan = ScanEngine.plan(folder: temp.url, using: rules)
    #expect(plan.map(\.source.lastPathComponent) == ["a.png"])
}

@Test func treatsAnOrdinaryFolderAsASingleUnitBoundForFallback() throws {
    let temp = try TempDirectory()
    let project = try temp.makeDirectory("My Project")
    try "x".write(to: project.appendingPathComponent("inner.png"), atomically: true, encoding: .utf8)

    let plan = ScanEngine.plan(folder: temp.url, using: rules)

    #expect(plan.count == 1, "the folder is one unit; its contents are never planned separately")
    #expect(plan[0].source.lastPathComponent == "My Project")
    #expect(plan[0].destination.category == "Other")
}

@Test func routesBundleFoldersByTheirExtension() throws {
    let temp = try TempDirectory()
    try temp.makeDirectory("Thing.app")

    let plan = ScanEngine.plan(folder: temp.url, using: rules)
    #expect(plan[0].destination.category == "Apps")
}

/// The plan is built from a `Set`, whose iteration order is arbitrary and
/// changes between runs. The preview list is a UI surface a user reads and
/// re-reads while deciding, so it has to come back in the same order every
/// time. Six entries, written in an order that is not the answer: an unsorted
/// plan matching by luck is a 1-in-720 event.
@Test func planIsOrderedByFileName() throws {
    let temp = try TempDirectory()
    for name in ["delta.png", "bravo.mp4", "foxtrot.png", "alpha.png", "charlie.mp4", "echo.png"] {
        try temp.writeFile(name)
    }

    let plan = ScanEngine.plan(folder: temp.url, using: rules)

    #expect(plan.map(\.source.lastPathComponent) ==
            ["alpha.png", "bravo.mp4", "charlie.mp4", "delta.png", "echo.png", "foxtrot.png"])
}

@Test func planningAnEmptyFolderYieldsNothing() throws {
    let temp = try TempDirectory()
    #expect(ScanEngine.plan(folder: temp.url, using: rules).isEmpty)
}

@Test func planningIsReadOnly() throws {
    let temp = try TempDirectory()
    try temp.writeFile("a.png")

    _ = ScanEngine.plan(folder: temp.url, using: rules)

    let names = try FileManager.default.contentsOfDirectory(atPath: temp.url.path)
    #expect(names == ["a.png"], "plan() must not move or create anything")
}

/// A file can vanish between the directory listing and the per-entry stat —
/// a download gets cancelled, or the user deletes something while the
/// Organize Now preview is being built. Simulated deterministically via an
/// injected provider instead of racing a real deletion against the scan.
@Test func aVanishedEntryIsSkippedNotForceUnwrapped() throws {
    let temp = try TempDirectory()
    try temp.writeFile("a.png")
    try temp.writeFile("ghost.mp4")

    let plan = ScanEngine.plan(folder: temp.url, using: rules) { url in
        url.lastPathComponent == "ghost.mp4" ? nil : FileFacts(url: url)
    }

    #expect(plan.map(\.source.lastPathComponent) == ["a.png"])
}

@Test func aPlanMarksBrowsableFoldersAndNotPackages() throws {
    let dir = try TempDirectory()
    try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("Project"),
                                            withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("Thing.app"),
                                            withIntermediateDirectories: true)
    try Data().write(to: dir.url.appendingPathComponent("a.png"))

    let plan = ScanEngine.plan(folder: dir.url, using: .defaults)
    func entry(_ name: String) -> PlannedMove? { plan.first { $0.source.lastPathComponent == name } }

    #expect(entry("Project")?.isFolder == true)
    #expect(entry("Thing.app")?.isFolder == false)
    #expect(entry("a.png")?.isFolder == false)
}
