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
