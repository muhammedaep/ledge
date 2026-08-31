import Testing
import Foundation
@testable import LedgeCore

private let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

private func facts(
    _ name: String,
    isDirectory: Bool = false,
    isPackage: Bool = false,
    date: Date = .distantPast
) -> FileFacts {
    FileFacts(url: root.appendingPathComponent(name),
              isDirectory: isDirectory,
              isPackage: isPackage,
              creationDate: date)
}

@Test func matchesByExtension() {
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])])
    let result = Categorizer.destination(for: facts("clip.mp4"), in: root, using: rules)
    #expect(result.category == "Videos")
    #expect(result.folder == root.appendingPathComponent("Videos"))
}

@Test func extensionMatchingIsCaseInsensitive() {
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])])
    #expect(Categorizer.destination(for: facts("CLIP.MP4"), in: root, using: rules).category == "Videos")
}

@Test func firstMatchingCategoryWins() {
    // The head of the list must *not* claim the extension, or "first matching"
    // and "first, period" give the same answer and the test cannot tell the
    // ordering guarantee from a bug that ignores it entirely.
    let rules = RuleSet(categories: [
        Category(name: "Design", extensions: ["psd"]),   // skipped: claims nothing here
        Category(name: "Images", extensions: ["png"]),   // the first genuine match
        Category(name: "Screenshots", extensions: ["png"])
    ])
    #expect(Categorizer.destination(for: facts("a.png"), in: root, using: rules).category == "Images")
}

@Test func customFallbackNameIsHonoured() {
    // `fallbackName` is user-editable and round-trips through RulesStore, so
    // the fallback must read it rather than hardcoding "Other".
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])],
                        fallbackName: "Misc")
    let result = Categorizer.destination(for: facts("mystery.xyz"), in: root, using: rules)
    #expect(result.category == "Misc")
    #expect(result.folder == root.appendingPathComponent("Misc"))
}

@Test func unknownExtensionFallsBack() {
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])])
    let result = Categorizer.destination(for: facts("mystery.xyz"), in: root, using: rules)
    #expect(result.category == "Other")
    #expect(result.folder == root.appendingPathComponent("Other"))
}

@Test func fileWithNoExtensionFallsBack() {
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])])
    #expect(Categorizer.destination(for: facts("README"), in: root, using: rules).category == "Other")
}

@Test func directoryFallsBackEvenWhenItsNameLooksLikeAnExtension() {
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])])
    let result = Categorizer.destination(for: facts("footage.mp4", isDirectory: true), in: root, using: rules)
    #expect(result.category == "Other")
}

@Test func directoryMatchesWhenARuleClaimsItsExtension() {
    // .app bundles are directories but must land in Apps.
    let rules = RuleSet(categories: [Category(name: "Apps", extensions: ["app"])])
    let result = Categorizer.destination(
        for: facts("Ice.app", isDirectory: true, isPackage: true), in: root, using: rules)
    #expect(result.category == "Apps")
}

/// Which bundle types match is macOS's question to answer, not a list this app
/// keeps: none of these extensions were on the allowlist this replaced, and a
/// user who adds one to a category expects their documents filed, not shelved
/// in the fallback.
@Test(arguments: ["sketch", "rtfd", "photoslibrary", "logicx"])
func anyPackageDirectoryMatchesWhenARuleClaimsItsExtension(ext: String) {
    let rules = RuleSet(categories: [Category(name: "Design", extensions: [ext])])
    let result = Categorizer.destination(
        for: facts("Thing.\(ext)", isDirectory: true, isPackage: true), in: root, using: rules)
    #expect(result.category == "Design")
}

/// The converse, and the reason the guard is not simply "a rule claims it":
/// a browsable directory stays browsable however familiar its extension looks.
@Test func aDirectoryTheSystemDoesNotCallAPackageNeverMatches() {
    let rules = RuleSet(categories: [Category(name: "Apps", extensions: ["app"])])
    let result = Categorizer.destination(
        for: facts("not-really.app", isDirectory: true, isPackage: false), in: root, using: rules)
    #expect(result.category == "Other")
}

/// The project's oldest structural rule, asserted end to end against a real
/// directory: a folder merely *named* like a file is not that file type.
///
/// Everything else pins this in two halves — `factsReportABrowsableFolderAsNotAPackage`
/// checks that a real `footage.mp4` directory reports `isPackage == false`, and
/// `directoryFallsBackEvenWhenItsNameLooksLikeAnExtension` checks that facts
/// shaped that way fall back — and two halves can drift apart without either of
/// them failing. This goes from a directory on disk, through the real
/// `FileFacts(url:)`, out the far side of `Categorizer`.
@Test func aRealFolderNamedLikeAVideoIsNotFiledAsAVideo() throws {
    let temp = try TempDirectory()
    let folder = try temp.makeDirectory("footage.mp4")

    let facts = try #require(FileFacts(url: folder))
    let rules = RuleSet(categories: [Category(name: "Videos", extensions: ["mp4"])])
    let result = Categorizer.destination(for: facts, in: temp.url, using: rules)

    #expect(result.category == "Other")
    #expect(result.folder == temp.url.appendingPathComponent("Other"))
}

@Test func byExtensionSubdivisionAddsAnUppercasedSubfolder() {
    let rules = RuleSet(categories: [
        Category(name: "Images", extensions: ["png"], subdivision: .byExtension)
    ])
    let result = Categorizer.destination(for: facts("a.png"), in: root, using: rules)
    #expect(result.folder == root.appendingPathComponent("Images").appendingPathComponent("PNG"))
}

@Test func byMonthSubdivisionUsesCreationDate() {
    var components = DateComponents()
    components.year = 2026
    components.month = 8
    components.day = 14
    let date = Calendar(identifier: .gregorian).date(from: components)!

    let rules = RuleSet(categories: [
        Category(name: "Images", extensions: ["png"], subdivision: .byMonth)
    ])
    let result = Categorizer.destination(for: facts("a.png", date: date), in: root, using: rules)
    #expect(result.folder == root.appendingPathComponent("Images").appendingPathComponent("2026-08"))
}

@Test func fallbackIsNeverSubdivided() {
    let rules = RuleSet(categories: [
        Category(name: "Images", extensions: ["png"], subdivision: .byExtension)
    ])
    let result = Categorizer.destination(for: facts("mystery.xyz"), in: root, using: rules)
    #expect(result.folder == root.appendingPathComponent("Other"))
}
