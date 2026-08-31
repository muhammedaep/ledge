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
