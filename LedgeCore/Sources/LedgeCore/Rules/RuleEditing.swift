import Foundation

// MARK: - The extensions field

public extension Category {
    /// The stored extensions as the one line of text the editor shows.
    ///
    /// The inverse of `parseExtensions`: feeding this back through it returns
    /// the same list, which is what lets the editor re-tidy a field in place
    /// without ever changing what it means.
    var extensionsField: String { extensions.joined(separator: " ") }

    /// Turns a typed or pasted extensions field into the list to store.
    ///
    /// This is a rule about what an extension *is*, not a formatting
    /// convenience, so it lives here rather than in the pane. `Categorizer`
    /// compares against `URL.pathExtension.lowercased()` — one lowercase word,
    /// no dot — and anything that cannot equal such a string can never match a
    /// file. A field that quietly stores `.PNG` or `tar.gz` does not fail
    /// loudly; it files nothing and looks correct while doing it.
    ///
    /// Tokens are separated by commas or any whitespace, so a pasted list
    /// survives whatever separators it arrived with, including a trailing one.
    /// Duplicates within the field collapse, keeping first position.
    static func parseExtensions(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for token in text.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            guard let ext = normalizedExtension(String(token)),
                  seen.insert(ext).inserted
            else { continue }
            result.append(ext)
        }
        return result
    }

    /// One token from the extensions field reduced to what `Categorizer` will
    /// actually compare against, or nil when nothing usable is left.
    ///
    /// Only the part after the last dot survives, because that is all
    /// `pathExtension` ever yields: `.png`, `*.png` and `archive.png` all mean
    /// `png`, and `.tar.gz` means `gz` — an entry stored as `tar.gz` would sit
    /// in the list looking like a rule and match nothing, forever. A token that
    /// is only dots, or that carries a path separator, has no last component to
    /// keep and is dropped.
    static func normalizedExtension(_ token: String) -> String? {
        let cleaned = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let last = cleaned.split(separator: ".").last else { return nil }
        let ext = String(last)
        guard !ext.contains("/"), !ext.contains(":"), !ext.contains("\0") else { return nil }
        return ext
    }
}

// MARK: - Folder names

public extension Category {
    /// Whether a name can be used as the folder a rule set files into.
    ///
    /// Both `Category.name` and `RuleSet.fallbackName` are appended to a URL as
    /// a single path component, so a name is not merely cosmetic. An empty one
    /// appends nothing and files every match back into the folder it was found
    /// in; `..` files into the parent; a name carrying `/` invents a folder
    /// hierarchy the user never asked for. None of those report an error — they
    /// just move the user's downloads somewhere they did not choose.
    static func isUsableFolderName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != ".." else { return false }
        return !trimmed.contains("/") && !trimmed.contains(":") && !trimmed.contains("\0")
    }

    /// The key two folder names are the same under.
    ///
    /// Matches how the volume behaves rather than how the strings compare:
    /// macOS file systems are case-insensitive by default and treat the two
    /// Unicode spellings of an accented character as one name, so `Images` and
    /// `images` are one folder no matter how the rule set spells them.
    static func folderNameKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .lowercased()
    }
}

// MARK: - What is wrong with a rule set

public extension RuleSet {
    /// Something wrong with a rule set, as data rather than as a sentence.
    ///
    /// The decision about what counts as wrong belongs here, where it is
    /// tested; the wording belongs to whatever is showing it. Every case names
    /// the category it is about so an editor can put it next to the right row —
    /// `nil` means the fallback, which is not a category.
    enum Problem: Hashable, Sendable {
        /// The name cannot be a folder, so this rule would file somewhere the
        /// user did not choose. The only problem that blocks saving.
        case unusableName(category: Category.ID?, name: String)
        /// Two rules name the same folder. Both are live and both file into it,
        /// so the editor shows two rules where the disk has one folder — with
        /// whichever subdivisions each of them sets, mixed together inside it.
        case duplicateName(category: Category.ID?, name: String)
        /// A leading dot makes the destination invisible in Finder. Legal, and
        /// occasionally deliberate, but rarely what someone means to type.
        case hiddenName(category: Category.ID?, name: String)
        /// A category claiming nothing never matches a file and never creates
        /// its folder.
        case noExtensions(category: Category.ID)
        /// An earlier category already claims this extension. First match wins,
        /// so this one will never see a file of that type — not a fault, but
        /// invisible from the row itself.
        case shadowedExtension(category: Category.ID, ext: String, claimedBy: String)

        /// Whether this must be fixed before the rule set can be saved.
        ///
        /// Only a name with no valid reading blocks. The rest are all states a
        /// user can legitimately mean, and refusing to save them would stop
        /// someone halfway through an edit — a category is empty for as long as
        /// it takes to type its first extension.
        public var blocksSaving: Bool {
            if case .unusableName = self { return true }
            return false
        }

        /// The category this is about, or nil when it is about the fallback.
        public var category: Category.ID? {
            switch self {
            case let .unusableName(id, _), let .duplicateName(id, _), let .hiddenName(id, _):
                return id
            case let .noExtensions(id), let .shadowedExtension(id, _, _):
                return id
            }
        }
    }

    /// Everything wrong with this rule set, in the order it should be shown:
    /// each category's problems where the category is, the fallback's last.
    var problems: [Problem] {
        var found: [Problem] = []

        var nameCounts: [String: Int] = [:]
        for name in categories.map(\.name) + [fallbackName] {
            nameCounts[Category.folderNameKey(name), default: 0] += 1
        }

        func nameProblems(_ name: String, _ id: Category.ID?) -> [Problem] {
            guard Category.isUsableFolderName(name) else {
                // A name that is not a folder name cannot also be a duplicate
                // or hidden one; saying so twice would just bury the fix.
                return [.unusableName(category: id, name: name)]
            }
            var out: [Problem] = []
            if nameCounts[Category.folderNameKey(name), default: 0] > 1 {
                out.append(.duplicateName(category: id, name: name))
            }
            if name.hasPrefix(".") {
                out.append(.hiddenName(category: id, name: name))
            }
            return out
        }

        // The winner of each extension, built in category order, which is the
        // order `Categorizer` matches in.
        var claimedBy: [String: String] = [:]
        for category in categories {
            found += nameProblems(category.name, category.id)
            if category.extensions.isEmpty {
                found.append(.noExtensions(category: category.id))
            }
            var own: Set<String> = []
            for ext in category.extensions where own.insert(ext).inserted {
                if let winner = claimedBy[ext] {
                    found.append(.shadowedExtension(category: category.id, ext: ext, claimedBy: winner))
                } else {
                    claimedBy[ext] = category.name
                }
            }
        }

        found += nameProblems(fallbackName, nil)
        return found
    }

    /// Whether this rule set is safe to commit.
    var canBeSaved: Bool { !problems.contains(where: \.blocksSaving) }
}
