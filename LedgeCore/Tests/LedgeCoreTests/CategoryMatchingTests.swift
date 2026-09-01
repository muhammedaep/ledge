import Testing
@testable import LedgeCore

@Test func extensionOnlyCategoryIgnoresTheName() {
    let images = Category(name: "Images", extensions: ["png"])
    #expect(images.matches(name: "anything.png", extension: "png"))
    #expect(!images.matches(name: "anything.jpg", extension: "jpg"))
}

@Test func patternOnlyCategoryIgnoresTheExtension() {
    let shots = Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    #expect(shots.matches(name: "CleanShot 1.png", extension: "png"))
    #expect(shots.matches(name: "CleanShot 1.mov", extension: "mov"))
    #expect(!shots.matches(name: "holiday.png", extension: "png"))
}

@Test func bothStatedMeansBothMustHold() {
    let delivery = Category(name: "Delivery", extensions: ["aep"], namePatterns: ["*_final*"])
    #expect(delivery.matches(name: "hero_final.aep", extension: "aep"))
    #expect(!delivery.matches(name: "hero_final.psd", extension: "psd"))
    #expect(!delivery.matches(name: "hero_draft.aep", extension: "aep"))
}

@Test func anyOneOfSeveralPatternsIsEnough() {
    let shots = Category(name: "Screenshots", extensions: [],
                         namePatterns: ["CleanShot *", "Screenshot *"])
    #expect(shots.matches(name: "Screenshot 2026-09-01.png", extension: "png"))
    #expect(shots.matches(name: "CleanShot 2026-09-01.png", extension: "png"))
}

@Test func aCategoryStatingNoConditionsClaimsNothing() {
    // Spec §1: the natural reading of "every stated condition holds" over an
    // empty set is *true*, which would make a half-typed rule in the editor
    // swallow the whole folder. This is the one place that reading is refused.
    let empty = Category(name: "Empty", extensions: [])
    #expect(!empty.matches(name: "anything.png", extension: "png"))
    #expect(!empty.matches(name: "", extension: ""))
}

@Test func aCategoryWithNoExtensionsStillRejectsAnExtensionlessNameItDoesNotMatch() {
    let shots = Category(name: "Screenshots", extensions: [], namePatterns: ["CleanShot *"])
    #expect(!shots.matches(name: "README", extension: ""))
}

@Test func anEmptyExtensionEntryDoesNotClaimAnExtensionlessFile() {
    // A hand-edited rules.json can carry `extensions: [""]`. Before patterns
    // existed, a guard ahead of `Category.matches` sent every extensionless
    // file straight to the fallback, so this entry was inert no matter where
    // it came from. That guard is gone now that a pattern-only rule needs to
    // see extensionless files — nothing here should resurrect the old one by
    // letting `""` claim it instead.
    let category = Category(name: "Everything", extensions: [""])
    #expect(!category.matches(name: "README", extension: ""))
}
