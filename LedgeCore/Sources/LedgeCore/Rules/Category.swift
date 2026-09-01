import Foundation

/// How a category splits its folder into subfolders.
public enum Subdivision: String, Codable, CaseIterable, Sendable {
    /// Everything goes directly in the category folder.
    case none
    /// `Images/PNG/`, `Images/JPG/` …
    case byExtension
    /// `Images/2026-08/` …
    case byMonth
}

/// One filing rule: a destination folder name and the conditions a file must
/// satisfy to be filed there.
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var extensions: [String]

    /// Glob patterns matched against the whole filename, extension included.
    ///
    /// Stored as typed, not lowercased. `extensions` is lowercased on the way
    /// in because `Categorizer` compares it against a lowercase
    /// `pathExtension`; patterns fold case at match time instead, and storing
    /// them folded would show the user something they did not write.
    public var namePatterns: [String]

    public var subdivision: Subdivision

    public init(
        id: UUID = UUID(),
        name: String,
        extensions: [String],
        namePatterns: [String] = [],
        subdivision: Subdivision = .none
    ) {
        self.id = id
        self.name = name
        // An empty entry is dropped, not just lowercased. `Categorizer` hands
        // `matches` an extensionless file's `pathExtension` as `""`, and
        // before patterns existed a guard ahead of this rule sent every such
        // file to the fallback, so `extensions: [""]` was inert wherever it
        // came from. That guard is gone now that a pattern-only rule needs to
        // see extensionless files, and `RuleEditing.parseExtensions` already
        // never produces this token — but `rules.json` is user-editable, and
        // a hand-added `""` would otherwise claim every extensionless
        // download for whichever category listed it.
        self.extensions = extensions.map { $0.lowercased() }.filter { !$0.isEmpty }
        self.namePatterns = namePatterns
        self.subdivision = subdivision
    }

    /// Whether this category claims a file.
    ///
    /// Every condition the category *states* must hold; a condition it leaves
    /// empty is not a constraint. That single rule covers all three useful
    /// shapes — extensions only, patterns only, both — without an all/any
    /// switch, and leaves every rule written before patterns existed behaving
    /// exactly as it did.
    ///
    /// The exception is a category that states nothing at all, which claims
    /// nothing rather than everything. Over an empty set the rule above reads
    /// *true*, and a rule half-typed in the editor is exactly that shape: it
    /// would swallow the whole folder between two keystrokes.
    ///
    /// `ext` is expected already lowercased, as `Categorizer` supplies it.
    public func matches(name: String, extension ext: String) -> Bool {
        if extensions.isEmpty && namePatterns.isEmpty { return false }
        if !extensions.isEmpty && !extensions.contains(ext) { return false }
        if !namePatterns.isEmpty
            && !namePatterns.contains(where: { Glob.matches(pattern: $0, name: name) }) {
            return false
        }
        return true
    }

    /// Hand-written so a `rules.json` saved before patterns existed still
    /// loads. Swift's synthesised decoder rejects a file missing any key, and
    /// every rule set already on disk is missing this one.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Same filter as the memberwise initializer, and for the same reason:
        // a hand-edited `rules.json` can carry `extensions: [""]`, which
        // would otherwise claim every extensionless file.
        extensions = try container.decode([String].self, forKey: .extensions)
            .map { $0.lowercased() }.filter { !$0.isEmpty }
        namePatterns = try container.decodeIfPresent([String].self, forKey: .namePatterns) ?? []
        subdivision = try container.decode(Subdivision.self, forKey: .subdivision)
    }
}
