import Testing
import Foundation
@testable import LedgeCore

private let root = URL(fileURLWithPath: "/tmp/root", isDirectory: true)

private func facts(_ name: String, isDirectory: Bool = false, date: Date = .distantPast) -> FileFacts {
    FileFacts(url: root.appendingPathComponent(name), isDirectory: isDirectory, creationDate: date)
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
    let rules = RuleSet(categories: [
        Category(name: "Design", extensions: ["png"]),
        Category(name: "Images", extensions: ["png"])
    ])
    #expect(Categorizer.destination(for: facts("a.png"), in: root, using: rules).category == "Design")
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
    let result = Categorizer.destination(for: facts("Ice.app", isDirectory: true), in: root, using: rules)
    #expect(result.category == "Apps")
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
