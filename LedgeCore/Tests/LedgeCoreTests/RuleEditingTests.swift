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

/// Rewriting the field to the stored spelling must not change what is stored.
///
/// The editor's field and its list update each other: typing reparses into the
/// list, and ending the edit rewrites the field from the list. If a rewritten
/// field parsed to anything but the same list, those two would take turns
/// changing each other for as long as the row was on screen.
@Test func tidyingTheFieldDoesNotChangeWhatIsStored() {
    for typed in ["png, .JPG  gif", ".tar.gz", "*.png", ".", "a/b png", "pdf, docx,",
                  "", "PNG .png png,", "  ", "\t.HEIC\n"] {
        let stored = Category.parseExtensions(typed)
        let tidied = Category(name: "x", extensions: stored).extensionsField
        #expect(Category.parseExtensions(tidied) == stored, "“\(typed)” does not settle")
        // And a second pass is a no-op, so the field stops moving.
        #expect(Category(name: "x", extensions: Category.parseExtensions(tidied)).extensionsField == tidied)
    }
}

// MARK: - What parsing changed

/// The two conventions everyone already assumes. Reporting these would put a
/// note under the field almost permanently.
@Test func lowercasingAndALeadingDotAreNotWorthReporting() {
    #expect(Category.extensionRewrites(in: "png") == [])
    #expect(Category.extensionRewrites(in: ".png") == [])
    #expect(Category.extensionRewrites(in: ".PNG") == [])
    #expect(Category.extensionRewrites(in: "PNG, .JPG  gif") == [])
    #expect(Category.extensionRewrites(in: "pdf, docx, txt,") == [])
}

/// A token that lost something it looked like it kept. This is the case worth
/// telling the user about: the field says one thing, the rule does another.
@Test func aTokenThatLostAComponentIsReported() {
    #expect(Category.extensionRewrites(in: ".tar.gz")
        == [Category.ExtensionRewrite(typed: ".tar.gz", stored: "gz")])
    #expect(Category.extensionRewrites(in: "*.png")
        == [Category.ExtensionRewrite(typed: "*.png", stored: "png")])
    #expect(Category.extensionRewrites(in: "archive.zip")
        == [Category.ExtensionRewrite(typed: "archive.zip", stored: "zip")])
}

@Test func aTokenThrownAwayEntirelyIsReported() {
    #expect(Category.extensionRewrites(in: "a/b")
        == [Category.ExtensionRewrite(typed: "a/b", stored: nil)])
    #expect(Category.extensionRewrites(in: "png a:b")
        == [Category.ExtensionRewrite(typed: "a:b", stored: nil)])
}

/// A lone dot had nothing in it to lose, so there is nothing to report.
@Test func punctuationThatCarriedNothingIsNotReported() {
    #expect(Category.extensionRewrites(in: ".") == [])
    #expect(Category.extensionRewrites(in: ". .. png") == [])
    #expect(Category.extensionRewrites(in: "") == [])
}

@Test func everyRewriteInAPastedFieldIsReportedInOrder() {
    #expect(Category.extensionRewrites(in: "png, .tar.gz, jpg, *.webp") == [
        Category.ExtensionRewrite(typed: ".tar.gz", stored: "gz"),
        Category.ExtensionRewrite(typed: "*.webp", stored: "webp")
    ])
}

/// The guarantee the editor's note depends on: whatever is reported as stored
/// is what `parseExtensions` actually stored.
@Test func aReportedRewriteMatchesWhatIsStored() {
    let text = "png, .tar.gz, a/b, *.webp"
    let stored = Category.parseExtensions(text)
    for rewrite in Category.extensionRewrites(in: text) {
        if let value = rewrite.stored {
            #expect(stored.contains(value), "\(rewrite.typed) claims \(value), which is not stored")
        } else {
            #expect(!stored.contains(rewrite.typed.lowercased()))
        }
    }
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

/// One decision, one function: a caller that needs to say *why* a name is
/// unusable reads it here instead of re-deriving "is it blank" beside it.
@Test func theFaultInANameIsNamed() {
    #expect(Category.folderNameFault("Images") == nil)

    #expect(Category.folderNameFault("") == .blank)
    #expect(Category.folderNameFault("   ") == .blank)
    #expect(Category.folderNameFault("\n") == .blank)
    #expect(Category.folderNameFault("\t ") == .blank)

    #expect(Category.folderNameFault(".") == .notAFolderName)
    #expect(Category.folderNameFault("..") == .notAFolderName)
    #expect(Category.folderNameFault("../Images") == .notAFolderName)
    #expect(Category.folderNameFault("a:b") == .notAFolderName)
}

@Test func folderNamesCompareTheWayTheFileSystemDoes() {
    // Case and Unicode spelling are folded, because a macOS volume folds them.
    #expect(Category.folderNameKey("Images") == Category.folderNameKey("images"))
    #expect(Category.folderNameKey("Café") == Category.folderNameKey("Cafe\u{0301}"))
    #expect(Category.folderNameKey("Images") != Category.folderNameKey("Videos"))

    // Surrounding whitespace is not folded, because no volume folds it:
    // ` Images ` and `Images` are two different folders everywhere, and calling
    // them one would make the editor's duplicate warning a false statement.
    #expect(Category.folderNameKey(" Images ") != Category.folderNameKey("Images"))
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

    #expect(rules.problems == [.unusableName(category: blank.id, name: "  ", fault: .blank)])
    #expect(!rules.canBeSaved)
}

@Test func anUnusableFallbackNameBlocksSavingToo() {
    let rules = RuleSet(categories: [Category(name: "Images", extensions: ["png"])],
                        fallbackName: "../Elsewhere")

    #expect(rules.problems == [
        .unusableName(category: nil, name: "../Elsewhere", fault: .notAFolderName)
    ])
    #expect(!rules.canBeSaved)
}

/// A newline-only name is blank, not a bad folder name. The pane words the two
/// differently, and it reads the difference from here rather than deciding it
/// again with a slightly different notion of whitespace.
@Test func aWhitespaceOnlyNameIsBlankWhateverTheWhitespaceIs() {
    let newline = Category(name: "\n", extensions: ["png"])
    let rules = RuleSet(categories: [newline])

    #expect(rules.problems == [.unusableName(category: newline.id, name: "\n", fault: .blank)])
}

/// An unusable name is reported once. Piling `duplicateName` on top of it would
/// bury the one fix that matters.
@Test func anUnusableNameIsReportedOnceEvenWhenRepeated() {
    let first = Category(name: "", extensions: ["png"])
    let second = Category(name: "", extensions: ["mp4"])
    let rules = RuleSet(categories: [first, second])

    #expect(rules.problems == [
        .unusableName(category: first.id, name: "", fault: .blank),
        .unusableName(category: second.id, name: "", fault: .blank)
    ])
}

/// Names that differ only in case are one folder on a case-insensitive volume —
/// the macOS default, but not a guarantee. `exact` is false here so the editor
/// can say "on a case-insensitive disk" rather than asserting it outright.
@Test func twoCategoriesNamingOneFolderAreFlaggedOnBothRows() {
    let first = Category(name: "Images", extensions: ["png"])
    let second = Category(name: "images", extensions: ["heic"])
    let rules = RuleSet(categories: [first, second])

    #expect(rules.problems == [
        .duplicateName(category: first.id, name: "Images", exact: false),
        .duplicateName(category: second.id, name: "images", exact: false)
    ])
    // A warning, not a refusal: both rules work, they just share one folder.
    #expect(rules.canBeSaved)
}

/// Identical names are one folder on every volume, so `exact` is true and the
/// editor can say so without hedging.
@Test func identicalNamesAreAnExactDuplicate() {
    let first = Category(name: "Images", extensions: ["png"])
    let second = Category(name: "Images", extensions: ["heic"])
    let rules = RuleSet(categories: [first, second])

    #expect(rules.problems == [
        .duplicateName(category: first.id, name: "Images", exact: true),
        .duplicateName(category: second.id, name: "Images", exact: true)
    ])
}

/// ` Images ` really is a different folder from `Images`, so it is not a
/// duplicate at all — reporting one would have been a false warning.
@Test func namesDifferingBySurroundingSpaceAreNotDuplicates() {
    let rules = RuleSet(categories: [
        Category(name: "Images", extensions: ["png"]),
        Category(name: " Images ", extensions: ["heic"])
    ])
    #expect(rules.problems.isEmpty)
}

@Test func aCategoryColldingWithTheFallbackIsFlagged() {
    let other = Category(name: "Other", extensions: ["torrent"])
    let rules = RuleSet(categories: [other], fallbackName: "Other")

    #expect(rules.problems == [
        .duplicateName(category: other.id, name: "Other", exact: true),
        .duplicateName(category: nil, name: "Other", exact: true)
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
