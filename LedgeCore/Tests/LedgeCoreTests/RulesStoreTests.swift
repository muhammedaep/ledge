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

    // The point of moving it aside rather than deleting it is that the user
    // can get their hand edits back, so the bytes have to actually be there.
    let recovered = try String(
        contentsOf: temp.url.appendingPathComponent(quarantined[0]), encoding: .utf8)
    #expect(recovered == "{ this is not json")
}

@Test func lastLoadWasCorruptClearsOnACleanReload() throws {
    let temp = try TempDirectory()
    let path = temp.url.appendingPathComponent("rules.json")
    try "{ not json".write(to: path, atomically: true, encoding: .utf8)

    let store = RulesStore(directory: temp.url)
    _ = store.load()
    #expect(store.lastLoadWasCorrupt)

    // The flag drives a "your rules were reset" banner. Once the file is
    // repaired it has to go back down, or the banner never clears.
    try store.save(.defaults)
    _ = store.load()
    #expect(!store.lastLoadWasCorrupt)
}

@Test func eachCorruptLoadGetsItsOwnQuarantineFile() throws {
    let temp = try TempDirectory()
    let path = temp.url.appendingPathComponent("rules.json")

    // Two corruptions back to back land inside the same wall-clock second, so
    // the timestamp alone does not make the names distinct. If the second
    // rename collides it fails silently and leaves the corrupt file in place,
    // where the next save destroys it.
    for text in ["{ first bad", "{ second bad"] {
        try text.write(to: path, atomically: true, encoding: .utf8)
        _ = RulesStore(directory: temp.url).load()
    }

    let quarantined = try FileManager.default
        .contentsOfDirectory(atPath: temp.url.path)
        .filter { $0.hasPrefix("rules.corrupt-") }
    #expect(quarantined.count == 2, "neither corrupt file may be lost to a name collision")
    #expect(!FileManager.default.fileExists(atPath: path.path),
            "a quarantined file must be moved out of the way, not left to be overwritten")

    let recovered = try Set(quarantined.map {
        try String(contentsOf: temp.url.appendingPathComponent($0), encoding: .utf8)
    })
    #expect(recovered == ["{ first bad", "{ second bad"])
}

@Test func saveCreatesTheDirectoryIfMissing() throws {
    let temp = try TempDirectory()
    let nested = temp.url.appendingPathComponent("Ledge", isDirectory: true)
    let store = RulesStore(directory: nested)

    try store.save(.defaults)
    #expect(FileManager.default.fileExists(atPath: nested.appendingPathComponent("rules.json").path))
}

// MARK: - Refusing an unusable write

/// The guard used to live in `AppState.updateRules`, where no test could reach
/// it: mutating it to a no-op killed nothing, because the app target has no
/// tests by design. Here it is reachable, so this test is the one that fails
/// when the refusal is removed.
@Test func saveRefusesRulesThatNameAFolderLedgeMustNotFileInto() throws {
    let temp = try TempDirectory()
    let store = RulesStore(directory: temp.url)
    let unusable = RuleSet(categories: [
        Category(name: "Images", extensions: ["png"]),
        Category(name: "  ", extensions: ["mp4"])
    ])

    #expect(throws: RuleSet.Unusable.self) { try store.save(unusable) }
    #expect(!FileManager.default.fileExists(atPath: temp.url.appendingPathComponent("rules.json").path))
}

/// A refused write must not damage what is already stored — otherwise a bad
/// save would cost the user the rules they had.
@Test func aRefusedSaveLeavesThePreviousRulesOnDisk() throws {
    let temp = try TempDirectory()
    let store = RulesStore(directory: temp.url)
    let good = RuleSet(categories: [Category(name: "Keep", extensions: ["png"])])
    try store.save(good)

    #expect(throws: RuleSet.Unusable.self) {
        try store.save(RuleSet(categories: [Category(name: "..", extensions: ["mp4"])]))
    }
    #expect(RulesStore(directory: temp.url).load() == good)
}

// MARK: - Repairing an unusable read

/// A hand-edited file that parses perfectly can still say something Ledge must
/// not act on. `Categorizer` appends the category name as a path component
/// without checking it, so a blank name files every match straight back into the
/// folder it came from — quietly, on every download.
@Test func loadRepairsACategoryThatCannotBeAFolder() throws {
    let temp = try TempDirectory()
    let path = temp.url.appendingPathComponent("rules.json")
    try """
    {
      "categories": [
        { "id": "\(UUID().uuidString)", "name": "Images", "extensions": ["png"], "subdivision": "none" },
        { "id": "\(UUID().uuidString)", "name": "", "extensions": ["mp4"], "subdivision": "none" }
      ],
      "fallbackName": "Other"
    }
    """.write(to: path, atomically: true, encoding: .utf8)

    let store = RulesStore(directory: temp.url)
    let loaded = store.load()

    #expect(loaded.categories.map(\.name) == ["Images"])
    #expect(store.lastLoadWasRepaired)
    #expect(!store.lastLoadWasCorrupt, "the file parsed; it was not corrupt")
    // The file itself is left alone — nothing was quarantined, and the user's
    // own edit is still there to be fixed by hand.
    #expect(FileManager.default.fileExists(atPath: path.path))
}

@Test func loadRevertsAnUnusableFallbackName() throws {
    let temp = try TempDirectory()
    try """
    {
      "categories": [
        { "id": "\(UUID().uuidString)", "name": "Images", "extensions": ["png"], "subdivision": "none" }
      ],
      "fallbackName": ".."
    }
    """.write(to: temp.url.appendingPathComponent("rules.json"), atomically: true, encoding: .utf8)

    let store = RulesStore(directory: temp.url)
    let loaded = store.load()

    #expect(loaded.fallbackName == "Other")
    #expect(store.lastLoadWasRepaired)
}

@Test func loadOfAGoodFileReportsNoRepair() throws {
    let temp = try TempDirectory()
    let store = RulesStore(directory: temp.url)
    try store.save(.defaults)

    let reader = RulesStore(directory: temp.url)
    #expect(reader.load() == RuleSet.defaults)
    #expect(!reader.lastLoadWasRepaired)
}

/// The two halves have to agree: anything `load` hands back must be something
/// `save` will accept, or a repaired file could never be written back.
@Test func whateverLoadReturnsCanBeSavedAgain() throws {
    let temp = try TempDirectory()
    try """
    {
      "categories": [
        { "id": "\(UUID().uuidString)", "name": "  ", "extensions": ["png"], "subdivision": "none" },
        { "id": "\(UUID().uuidString)", "name": "a/b", "extensions": ["mp4"], "subdivision": "none" }
      ],
      "fallbackName": "."
    }
    """.write(to: temp.url.appendingPathComponent("rules.json"), atomically: true, encoding: .utf8)

    let loaded = RulesStore(directory: temp.url).load()
    try RulesStore(directory: temp.url).save(loaded)   // must not throw
    #expect(RulesStore(directory: temp.url).load() == loaded)
}
