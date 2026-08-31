import Testing
import Foundation
@testable import LedgeCore

// MARK: - Parsing the extensions field

@Test func parseSplitsOnCommasAndAnyWhitespace() {
    #expect(Category.parseExtensions("png, jpg gif") == ["png", "jpg", "gif"])
    #expect(Category.parseExtensions("png\tjpg\ngif") == ["png", "jpg", "gif"])
    #expect(Category.parseExtensions("png,,jpg") == ["png", "jpg"])
    #expect(Category.parseExtensions("png,   ,  jpg") == ["png", "jpg"])
}

@Test func parseStripsLeadingDotsAndLowercases() {
    #expect(Category.parseExtensions("png, .JPG  gif") == ["png", "jpg", "gif"])
    #expect(Category.parseExtensions(".PNG") == ["png"])
    #expect(Category.parseExtensions("HEIC") == ["heic"])
}

@Test func parseDropsWhatCouldNeverBeAnExtension() {
    #expect(Category.parseExtensions("") == [])
    #expect(Category.parseExtensions("   ") == [])
    #expect(Category.parseExtensions(".") == [])
    #expect(Category.parseExtensions(". .. png") == ["png"])
    #expect(Category.parseExtensions("a/b png") == ["png"])
}

@Test func parseCollapsesDuplicatesKeepingFirstPosition() {
    #expect(Category.parseExtensions("png jpg png") == ["png", "jpg"])
    #expect(Category.parseExtensions("PNG .png png,") == ["png"])
}

@Test func parseSurvivesAPastedLineWithATrailingComma() {
    #expect(Category.parseExtensions("pdf, docx, txt,") == ["pdf", "docx", "txt"])
    #expect(Category.parseExtensions(" .pdf , .DOCX ,\t.txt , ") == ["pdf", "docx", "txt"])
}

/// `Categorizer` compares against `pathExtension`, which is only ever the part
/// after the last dot. An entry it cannot equal is a rule that never fires.
@Test func parseKeepsOnlyWhatPathExtensionCouldYield() {
    #expect(Category.parseExtensions(".tar.gz") == ["gz"])
    #expect(Category.parseExtensions("*.png") == ["png"])
    #expect(Category.parseExtensions("archive.zip") == ["zip"])
}

@Test func parsedExtensionsMatchWhatCategorizerCompares() {
    for text in ["PNG", ".Png", "*.png", "photo.png"] {
        let parsed = Category.parseExtensions(text)
        let fileExtension = URL(fileURLWithPath: "/tmp/photo.PNG").pathExtension.lowercased()
        #expect(parsed == [fileExtension], "\(text) does not match a real .PNG file")
    }
}

@Test func theFieldRoundTripsThroughParsing() {
    let category = Category(name: "Images", extensions: ["png", "jpg", "gif"])
    #expect(category.extensionsField == "png jpg gif")
    #expect(Category.parseExtensions(category.extensionsField) == category.extensions)
}

// MARK: - Folder names

@Test func aFolderNameMustBeAFolderName() {
    #expect(Category.isUsableFolderName("Images"))
    #expect(Category.isUsableFolderName("Ekran Görüntüleri"))
    #expect(Category.isUsableFolderName(".hidden"))   // legal, only warned about

    #expect(!Category.isUsableFolderName(""))
    #expect(!Category.isUsableFolderName("   "))
    #expect(!Category.isUsableFolderName("."))
    #expect(!Category.isUsableFolderName(".."))
    #expect(!Category.isUsableFolderName("../Images"))
    #expect(!Category.isUsableFolderName("Images/Raw"))
    #expect(!Category.isUsableFolderName("a:b"))
}

@Test func folderNamesCompareTheWayTheFileSystemDoes() {
    #expect(Category.folderNameKey("Images") == Category.folderNameKey("images"))
    #expect(Category.folderNameKey(" Images ") == Category.folderNameKey("Images"))
    #expect(Category.folderNameKey("Café") == Category.folderNameKey("Cafe\u{0301}"))
    #expect(Category.folderNameKey("Images") != Category.folderNameKey("Videos"))
}

// MARK: - Problems

@Test func theDefaultsHaveNothingWrongWithThem() {
    #expect(RuleSet.defaults.problems.isEmpty)
    #expect(RuleSet.defaults.canBeSaved)
}

/// `RuleSet.defaults` is a `static let`, so its categories keep the same ids
/// for the life of the process. An editor showing the defaults and then
/// resetting to them therefore sees the *same* rows come back, not new ones —
/// which is why the rules pane resyncs each row's text field from the list
/// rather than trusting SwiftUI to rebuild the row.
@Test func theDefaultsKeepTheirIdentityAcrossAccesses() {
    #expect(RuleSet.defaults.categories.map(\.id) == RuleSet.defaults.categories.map(\.id))
}

@Test func anUnusableNameBlocksSaving() {
    let blank = Category(name: "  ", extensions: ["png"])
    let rules = RuleSet(categories: [blank])

    #expect(rules.problems == [.unusableName(category: blank.id, name: "  ")])
    #expect(!rules.canBeSaved)
}

@Test func anUnusableFallbackNameBlocksSavingToo() {
    let rules = RuleSet(categories: [Category(name: "Images", extensions: ["png"])],
                        fallbackName: "../Elsewhere")

    #expect(rules.problems == [.unusableName(category: nil, name: "../Elsewhere")])
    #expect(!rules.canBeSaved)
}

/// An unusable name is reported once. Piling `duplicateName` on top of it would
/// bury the one fix that matters.
@Test func anUnusableNameIsReportedOnceEvenWhenRepeated() {
    let first = Category(name: "", extensions: ["png"])
    let second = Category(name: "", extensions: ["mp4"])
    let rules = RuleSet(categories: [first, second])

    #expect(rules.problems == [
        .unusableName(category: first.id, name: ""),
        .unusableName(category: second.id, name: "")
    ])
}

@Test func twoCategoriesNamingOneFolderAreFlaggedOnBothRows() {
    let first = Category(name: "Images", extensions: ["png"])
    let second = Category(name: "images", extensions: ["heic"])
    let rules = RuleSet(categories: [first, second])

    #expect(rules.problems == [
        .duplicateName(category: first.id, name: "Images"),
        .duplicateName(category: second.id, name: "images")
    ])
    // A warning, not a refusal: both rules work, they just share one folder.
    #expect(rules.canBeSaved)
}

@Test func aCategoryColldingWithTheFallbackIsFlagged() {
    let other = Category(name: "Other", extensions: ["torrent"])
    let rules = RuleSet(categories: [other], fallbackName: "Other")

    #expect(rules.problems == [
        .duplicateName(category: other.id, name: "Other"),
        .duplicateName(category: nil, name: "Other")
    ])
}

@Test func aHiddenDestinationIsWarnedAboutButAllowed() {
    let hidden = Category(name: ".Stash", extensions: ["png"])
    let rules = RuleSet(categories: [hidden])

    #expect(rules.problems == [.hiddenName(category: hidden.id, name: ".Stash")])
    #expect(rules.canBeSaved)
}

@Test func aCategoryClaimingNothingIsFlagged() {
    let empty = Category(name: "New Category", extensions: [])
    let rules = RuleSet(categories: [empty])

    #expect(rules.problems == [.noExtensions(category: empty.id)])
    #expect(rules.canBeSaved)
}

@Test func anExtensionClaimedEarlierIsFlaggedOnTheLaterCategory() {
    let images = Category(name: "Images", extensions: ["png", "jpg"])
    let screenshots = Category(name: "Screenshots", extensions: ["png", "heic"])
    let rules = RuleSet(categories: [images, screenshots])

    #expect(rules.problems == [
        .shadowedExtension(category: screenshots.id, ext: "png", claimedBy: "Images")
    ])
    #expect(rules.canBeSaved)
}

/// Moving the later category above the earlier one is what fixes it, which is
/// the whole reason the order is editable.
@Test func reorderingMovesTheShadowToTheOtherCategory() {
    let images = Category(name: "Images", extensions: ["png", "jpg"])
    let screenshots = Category(name: "Screenshots", extensions: ["png"])
    let reordered = RuleSet(categories: [screenshots, images])

    #expect(reordered.problems == [
        .shadowedExtension(category: images.id, ext: "png", claimedBy: "Screenshots")
    ])
}

/// A hand-edited rules.json can hold the same extension twice in one category.
/// That is not shadowing — the category still wins it — so it is not reported.
@Test func aCategoryDoesNotShadowItself() {
    let rules = RuleSet(categories: [Category(name: "Images", extensions: ["png", "png"])])
    #expect(rules.problems.isEmpty)
}

@Test func problemsAreOrderedByCategoryWithTheFallbackLast() {
    let images = Category(name: "Images", extensions: [])
    let rules = RuleSet(categories: [images], fallbackName: ".Other")

    #expect(rules.problems == [
        .noExtensions(category: images.id),
        .hiddenName(category: nil, name: ".Other")
    ])
}
