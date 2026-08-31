import Testing
import Foundation
@testable import LedgeCore

@Test func defaultRuleSetCoversCommonDownloadTypes() {
    let rules = RuleSet.defaults
    let names = rules.categories.map(\.name)

    #expect(names.contains("Images"))
    #expect(names.contains("Videos"))
    #expect(names.contains("Audio"))
    #expect(names.contains("Documents"))
    #expect(names.contains("Archives"))
    #expect(names.contains("Apps"))
    #expect(names.contains("Design"))
    #expect(names.contains("Fonts"))
    #expect(rules.fallbackName == "Other")
}

@Test func defaultExtensionsAreLowercasedAndDotless() {
    for category in RuleSet.defaults.categories {
        for ext in category.extensions {
            #expect(ext == ext.lowercased(), "\(ext) is not lowercased")
            #expect(!ext.hasPrefix("."), "\(ext) has a leading dot")
        }
    }
}

@Test func noExtensionAppearsInTwoCategories() {
    var seen: Set<String> = []
    for category in RuleSet.defaults.categories {
        for ext in category.extensions {
            #expect(!seen.contains(ext), "\(ext) is claimed twice")
            seen.insert(ext)
        }
    }
}

@Test func ruleSetSurvivesEncodeDecode() throws {
    let original = RuleSet.defaults
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(RuleSet.self, from: data)
    #expect(decoded == original)
}
