import Testing
import Foundation
@testable import LedgeCore

// `destinationFolderNames` is what stops a filing pass from filing its own
// output. The live watcher needs it as much as Organize Now does: the first
// automatic move creates the category folder, the watcher sees that folder
// appear, and without this guard the next event files `Documents` into
// `Other/Documents`, dragging everything already filed there with it.

@Test func destinationNamesCoverEveryCategoryAndTheFallback() {
    let rules = RuleSet(
        categories: [
            Category(name: "Images", extensions: ["png"]),
            Category(name: "Videos", extensions: ["mp4"])
        ],
        fallbackName: "Unsorted"
    )

    #expect(rules.destinationFolderNames == ["Images", "Videos", "Unsorted"])
}

@Test func theFallbackIsIncludedEvenWithNoCategories() {
    let rules = RuleSet(categories: [], fallbackName: "Other")

    #expect(rules.destinationFolderNames == ["Other"])
}

@Test func aCategoryNamedLikeTheFallbackDoesNotDuplicate() {
    let rules = RuleSet(
        categories: [Category(name: "Other", extensions: ["bin"])],
        fallbackName: "Other"
    )

    #expect(rules.destinationFolderNames == ["Other"])
}

@Test func everyDefaultCategoryFolderIsADestination() {
    let names = RuleSet.defaults.destinationFolderNames

    for category in RuleSet.defaults.categories {
        #expect(names.contains(category.name))
    }
    #expect(names.contains(RuleSet.defaults.fallbackName))
}

// The name test is case- and path-sensitive on purpose: it is compared against
// `URL.lastPathComponent`, so anything that is not an exact top-level folder
// name must stay a filing candidate rather than being silently skipped.

@Test func matchingIsExactSoUnrelatedNamesStayFilingCandidates() {
    let names = RuleSet.defaults.destinationFolderNames

    #expect(!names.contains("Documents Backup"))
    #expect(!names.contains("my-documents"))
    #expect(!names.contains("Documents.zip"))
}

// Subdivision folders live *inside* a category folder and both filing paths
// read at depth 1, so they are deliberately absent rather than overlooked.

@Test func subdivisionFolderNamesAreNotListed() {
    let rules = RuleSet(
        categories: [Category(name: "Images", extensions: ["png"], subdivision: .byExtension)],
        fallbackName: "Other"
    )

    #expect(rules.destinationFolderNames == ["Images", "Other"])
    #expect(!rules.destinationFolderNames.contains("PNG"))
}

// ScanEngine reads the same property, so the two filing paths cannot drift
// apart into disagreeing about what counts as a destination.

@Test func scanEngineSkipsEveryDestinationFolderName() throws {
    let temp = try TempDirectory()
    let rules = RuleSet(
        categories: [Category(name: "Images", extensions: ["png"])],
        fallbackName: "Other"
    )

    try temp.makeDirectory("Images")
    try temp.makeDirectory("Other")
    try temp.writeFile("shot.png")

    let plan = ScanEngine.plan(folder: temp.url, using: rules)

    #expect(plan.map { $0.source.lastPathComponent } == ["shot.png"])
}
