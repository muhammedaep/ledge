import Testing
import Foundation
@testable import LedgeCore

private func ruleSet(_ categories: [LedgeCore.Category], applied: [String] = []) -> RuleSet {
    RuleSet(categories: categories, fallbackName: "Other", appliedMigrations: applied)
}

@Test func screenshotsIsInsertedAboveThePngClaimant() {
    let before = ruleSet([
        Category(name: "Documents", extensions: ["pdf"]),
        Category(name: "Images", extensions: ["png", "jpg"]),
        Category(name: "Code", extensions: ["json"])
    ])
    let after = before.migrated()
    #expect(after.categories.map(\.name) == ["Documents", "Screenshots", "Images", "Code"])
}

@Test func screenshotsGoesFirstWhenNothingClaimsPng() {
    let before = ruleSet([Category(name: "Documents", extensions: ["pdf"])])
    #expect(before.migrated().categories.map(\.name) == ["Screenshots", "Documents"])
}

@Test func migrationRecordsItsMarker() {
    let after = ruleSet([Category(name: "Images", extensions: ["png"])]).migrated()
    #expect(after.appliedMigrations.contains(RuleSet.screenshotsMigration))
}

@Test func migrationIsANoOpOnceTheMarkerIsRecorded() {
    // This is what stops a rule the user deleted from coming back on the next
    // launch. Without the marker the migration is not a migration, it is a
    // policy.
    let deleted = ruleSet([Category(name: "Images", extensions: ["png"])],
                          applied: [RuleSet.screenshotsMigration])
    let after = deleted.migrated()
    #expect(after.categories.map(\.name) == ["Images"])
    #expect(after == deleted)
}

@Test func anExistingScreenshotsCategoryIsNotDuplicated() {
    let existing = ruleSet([
        Category(name: "screenshots", extensions: ["png"]),
        Category(name: "Images", extensions: ["png"])
    ])
    let after = existing.migrated()
    #expect(after.categories.count == 2)
    #expect(after.appliedMigrations.contains(RuleSet.screenshotsMigration))
}

@Test func migrationRespectsAReorderedRuleSet() {
    let reordered = ruleSet([
        Category(name: "Images", extensions: ["png"]),
        Category(name: "Documents", extensions: ["pdf"])
    ])
    #expect(reordered.migrated().categories.map(\.name) == ["Screenshots", "Images", "Documents"])
}

@Test func aPatternOnlyCategoryIsNotFlaggedAsEmpty() {
    let rules = RuleSet(categories: [
        Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    ])
    #expect(!rules.problems.contains { if case .noConditions = $0 { return true }; return false })
}

@Test func aCategoryWithNeitherExtensionsNorPatternsIsFlagged() {
    let rules = RuleSet(categories: [Category(name: "Empty", extensions: [])])
    #expect(rules.problems.contains { if case .noConditions = $0 { return true }; return false })
}

@Test func theShippedScreenshotsRuleCatchesRealScreenshotNames() {
    let shots = RuleSet.screenshotsCategory
    for name in ["CleanShot 2026-09-01 at 11.14.08@2x.png",
                 "Screenshot 2026-09-01 at 11.14.08.png",
                 "Screen Shot 2020-01-01 at 09.00.00.png"] {
        #expect(shots.matches(name: name, extension: "png"), "did not claim \(name)")
    }
    #expect(!shots.matches(name: "holiday.png", extension: "png"))
}

@Test func defaultsAreAlreadyMigrated() {
    // A fresh install ships the category, so it must also ship the marker —
    // otherwise the first launch would try to insert a second one.
    #expect(RuleSet.defaults.appliedMigrations.contains(RuleSet.screenshotsMigration))
    #expect(RuleSet.defaults.migrated() == RuleSet.defaults)
}

@Test func defaultsPutScreenshotsAboveImages() {
    let names = RuleSet.defaults.categories.map(\.name)
    let shots = names.firstIndex(of: "Screenshots")
    let images = names.firstIndex(of: "Images")
    #expect(shots != nil)
    #expect(images != nil)
    #expect(shots! < images!)
}
