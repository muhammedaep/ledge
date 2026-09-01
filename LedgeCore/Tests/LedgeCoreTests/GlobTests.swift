import Testing
@testable import LedgeCore

@Test func literalPatternMatchesOnlyItself() {
    #expect(Glob.matches(pattern: "notes.txt", name: "notes.txt"))
    #expect(!Glob.matches(pattern: "notes.txt", name: "notes.txt.bak"))
    #expect(!Glob.matches(pattern: "notes.txt", name: "my notes.txt"))
}

@Test func starMatchesARunOfCharacters() {
    #expect(Glob.matches(pattern: "CleanShot *", name: "CleanShot 2026-09-01 at 11.14.08@2x.png"))
    #expect(!Glob.matches(pattern: "CleanShot *", name: "Cleanshot.png"))
}

@Test func starMatchesNothingAtAll() {
    #expect(Glob.matches(pattern: "report*.pdf", name: "report.pdf"))
}

@Test func starMatchesAtEveryPosition() {
    #expect(Glob.matches(pattern: "*.png", name: "a.png"))
    #expect(Glob.matches(pattern: "IMG*", name: "IMG_0001.heic"))
    #expect(Glob.matches(pattern: "*final*", name: "hero_final_v2.aep"))
}

@Test func multipleStarsBacktrackCorrectly() {
    #expect(Glob.matches(pattern: "*a*b*c", name: "xxaxxbxxc"))
    #expect(!Glob.matches(pattern: "*a*b*c", name: "xxaxxbxxd"))
}

@Test func questionMarkMatchesExactlyOneCharacter() {
    #expect(Glob.matches(pattern: "IMG_????.png", name: "IMG_0042.png"))
    #expect(!Glob.matches(pattern: "IMG_????.png", name: "IMG_042.png"))
    #expect(!Glob.matches(pattern: "IMG_????.png", name: "IMG_00042.png"))
}

@Test func matchingFoldsCaseBothWays() {
    #expect(Glob.matches(pattern: "cleanshot *", name: "CleanShot 1.png"))
    #expect(Glob.matches(pattern: "CleanShot *", name: "cleanshot 1.png"))
    #expect(Glob.matches(pattern: "RÉSUMÉ*", name: "résumé.pdf"))
}

@Test func emptyPatternMatchesOnlyAnEmptyName() {
    #expect(Glob.matches(pattern: "", name: ""))
    #expect(!Glob.matches(pattern: "", name: "a"))
}

@Test func aLoneStarMatchesEverythingIncludingNothing() {
    #expect(Glob.matches(pattern: "*", name: ""))
    #expect(Glob.matches(pattern: "*", name: "anything at all.png"))
}

@Test func foldingIsLocaleIndependentForTheTurkishDottedI() {
    // Pins the spec's decision (§2): `matches` folds case with `lowercased()`,
    // not `lowercased(with: Locale.current)`. Under a Turkish locale the
    // latter maps `I` to `ı`, not `i`, so a pattern written on a Turkish Mac
    // would stop matching the same file on an English one. Every other test
    // in this file passes under both foldings — measured by mutating this
    // line to `lowercased(with: Locale.current)` and watching all ten stay
    // green — because none of their fixtures cross the letter Turkish treats
    // differently. This one does: `IMG*`'s `I` only matches `img_0001.heic`'s
    // `i` if the fold is locale-independent.
    #expect(Glob.matches(pattern: "IMG*", name: "img_0001.heic"))
}

@Test func aLiteralStarInANameIsNotMatchableExactly() {
    // Documented limit (spec §2): there is no escaping, so `*` in a pattern is
    // always the metacharacter. This test pins the limit down rather than
    // leaving it as folklore.
    #expect(Glob.matches(pattern: "star*.png", name: "star*.png"))
    #expect(Glob.matches(pattern: "star*.png", name: "starlight.png"))
}
