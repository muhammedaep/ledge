import Testing
import Foundation
@testable import LedgeCore

@Test func loadReturnsDefaultsWhenNoFileExists() throws {
    let temp = try TempDirectory()
    let store = RulesStore(directory: temp.url)
    #expect(store.load() == RuleSet.defaults)
}

@Test func savedRulesAreLoadedBack() throws {
    let temp = try TempDirectory()
    let store = RulesStore(directory: temp.url)
    let custom = RuleSet(categories: [Category(name: "Only", extensions: ["zzz"])],
                         fallbackName: "Misc")

    try store.save(custom)
    #expect(RulesStore(directory: temp.url).load() == custom)
}

@Test func corruptFileIsQuarantinedAndDefaultsRestored() throws {
    let temp = try TempDirectory()
    let path = temp.url.appendingPathComponent("rules.json")
    try "{ this is not json".write(to: path, atomically: true, encoding: .utf8)

    let store = RulesStore(directory: temp.url)
    #expect(store.load() == RuleSet.defaults)
    #expect(store.lastLoadWasCorrupt)

    let quarantined = try FileManager.default
        .contentsOfDirectory(atPath: temp.url.path)
        .filter { $0.hasPrefix("rules.corrupt-") }
    #expect(quarantined.count == 1)
}

@Test func saveCreatesTheDirectoryIfMissing() throws {
    let temp = try TempDirectory()
    let nested = temp.url.appendingPathComponent("Ledge", isDirectory: true)
    let store = RulesStore(directory: nested)

    try store.save(.defaults)
    #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("rules.json").path))
}
