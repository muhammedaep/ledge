import Foundation

// MARK: - The extensions field

public extension Category {
    /// The stored extensions as the one line of text the editor shows.
    ///
    /// The inverse of `parseExtensions`: feeding this back through it returns
    /// the same list, which is what lets the editor re-tidy a field in place
    /// without ever changing what it means.
    var extensionsField: String { extensions.joined(separator: " ") }

    /// The stored patterns as the text the editor shows, one per line.
    ///
    /// The inverse of `parseNamePatterns`, so feeding this back through it
    /// returns the same list.
    var namePatternsField: String { namePatterns.joined(separator: "\n") }

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

    /// Turns a typed or pasted patterns field into the list to store.
    ///
    /// One pattern per line, and the separator is not negotiable: the
    /// extensions field splits on commas or whitespace, and a pattern contains
    /// spaces — `CleanShot *` split that way stores two patterns, the second
    /// being `*`, which claims every file in the folder. A filename may contain
    /// a comma too. A newline is the only separator a filename cannot contain.
    ///
    /// Patterns are stored as typed. `parseExtensions` lowercases because
    /// `Categorizer` compares against a lowercase `pathExtension`; `Glob` folds
    /// case at match time instead, so folding here would only show the user
    /// something they did not write.
    ///
    /// Duplicates within the field collapse, keeping first position, as the
    /// extensions field does.
    static func parseNamePatterns(_ text: String) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let pattern = line.trimmingCharacters(in: .whitespaces)
            guard !pattern.isEmpty, seen.insert(pattern).inserted else { continue }
            result.append(pattern)
        }
        return result
    }
}

// MARK: - What parsing changed

public extension Category {
    /// A token the user typed that is not stored the way they typed it.
    struct ExtensionRewrite: Hashable, Sendable {
        /// The token exactly as typed.
        public let typed: String
        /// What is stored for it, or nil when it was dropped entirely.
        public let stored: String?

        public init(typed: String, stored: String?) {
            self.typed = typed
            self.stored = stored
        }
    }

    /// The tokens in a typed field that parsing changed in a way the user could
    /// not have predicted, so an editor can *say* so rather than only showing
    /// the result and hoping it is noticed.
    ///
    /// Lowercasing and dots at either edge are deliberately not reported.
    /// Everyone types `.PNG` sometimes and everyone expects it to mean `png`;
    /// reporting that would keep a note under the field almost permanently and
    /// train the user to ignore the one case that matters. What is reported is a
    /// token that lost something it looked like it kept — `.tar.gz` stored as
    /// `gz`, `*.png` as `png` — or one thrown away entirely.
    ///
    /// A *trailing* dot is an edge dot for the same reason a leading one is,
    /// and treating it as anything else made the note lie. `png.` stores `png`,
    /// so a note saying it kept "the part after the last dot" described an
    /// empty string. It fired mid-edit, too: typing `.tar.gz` passes through
    /// `.tar.`, putting a false sentence under the field during the very edit
    /// the note exists for.
    static func extensionRewrites(in text: String) -> [ExtensionRewrite] {
        var rewrites: [ExtensionRewrite] = []
        for token in text.split(whereSeparator: { $0 == "," || $0.isWhitespace }) {
            let typed = String(token)
            // What the expected conventions alone would produce. A token that
            // survives as this held no surprise worth reporting.
            let expected = typed.lowercased().trimmingCharacters(in: Self.dots)
            guard !expected.isEmpty else { continue }
            let stored = normalizedExtension(typed)
            guard stored != expected else { continue }
            rewrites.append(ExtensionRewrite(typed: typed, stored: stored))
        }
        return rewrites
    }

    private static let dots = CharacterSet(charactersIn: ".")
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
        folderNameFault(name) == nil
    }

    /// Why a name cannot be a folder, or nil when it can be.
    ///
    /// One function rather than two, because a caller that needs to *say* what
    /// is wrong would otherwise re-derive "is it blank" beside this one, and
    /// the two definitions drift the moment either changes.
    static func folderNameFault(_ name: String) -> NameFault? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .blank }
        guard trimmed != ".", trimmed != "..",
              !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.contains("\0")
        else { return .notAFolderName }
        return nil
    }

    /// What is wrong with a name that cannot be a folder.
    enum NameFault: Hashable, Sendable {
        /// Nothing to name a folder with.
        case blank
        /// Something is there, but it names a place instead of a folder — `..`,
        /// or a name carrying a path separator.
        case notAFolderName
    }

    /// The key two folder names are the same under.
    ///
    /// Matches how the volume behaves rather than how the strings compare: a
    /// macOS volume is case-insensitive by default and treats the two Unicode
    /// spellings of an accented character as one name, so `Images` and `images`
    /// are one folder no matter how the rule set spells them.
    ///
    /// Surrounding whitespace is deliberately *not* trimmed here, though
    /// `folderNameFault` trims to decide whether anything is there at all.
    /// ` Images ` and `Images` are two different folders on every volume, so
    /// folding them together here would have made the editor tell the user they
    /// share one — which is simply untrue.
    static func folderNameKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
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
        case unusableName(category: Category.ID?, name: String, fault: Category.NameFault)
        /// Two rules name the same folder. Both are live and both file into it,
        /// so the editor shows two rules where the disk has one folder — with
        /// whichever subdivisions each of them sets, mixed together inside it.
        ///
        /// `exact` separates the two ways that happens, because only one of
        /// them is true everywhere. Identical names are one folder on any
        /// volume. Names differing only in case or Unicode spelling are one
        /// folder on a case-insensitive volume, which is the macOS default but
        /// not a guarantee — a case-sensitive APFS volume really does keep
        /// `Images` and `images` apart.
        case duplicateName(category: Category.ID?, name: String, exact: Bool)
        /// A leading dot makes the destination invisible in Finder. Legal, and
        /// occasionally deliberate, but rarely what someone means to type.
        case hiddenName(category: Category.ID?, name: String)
        /// The category states no conditions at all — no extensions and no
        /// patterns — so nothing can ever match it. Renamed from
        /// `noExtensions`, which stopped being true the moment a category could
        /// be pattern-only: a Screenshots rule has no extensions by design, and
        /// warning about it would mean Ledge shipping a rule and immediately
        /// calling it a mistake.
        case noConditions(category: Category.ID)
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
            case let .unusableName(id, _, _), let .duplicateName(id, _, _), let .hiddenName(id, _):
                return id
            case let .noConditions(id), let .shadowedExtension(id, _, _):
                return id
            }
        }
    }

    /// Everything wrong with this rule set, in the order it should be shown:
    /// each category's problems where the category is, the fallback's last.
    var problems: [Problem] {
        var found: [Problem] = []

        let allNames = categories.map(\.name) + [fallbackName]
        var nameCounts: [String: Int] = [:]
        var exactCounts: [String: Int] = [:]
        for name in allNames {
            nameCounts[Category.folderNameKey(name), default: 0] += 1
            exactCounts[name, default: 0] += 1
        }

        func nameProblems(_ name: String, _ id: Category.ID?) -> [Problem] {
            if let fault = Category.folderNameFault(name) {
                // A name that is not a folder name cannot also be a duplicate
                // or hidden one; saying so twice would just bury the fix.
                return [.unusableName(category: id, name: name, fault: fault)]
            }
            var out: [Problem] = []
            if nameCounts[Category.folderNameKey(name), default: 0] > 1 {
                out.append(.duplicateName(
                    category: id, name: name, exact: exactCounts[name, default: 0] > 1))
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
            if category.extensions.isEmpty && category.namePatterns.isEmpty {
                found.append(.noConditions(category: category.id))
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

// MARK: - Refusing and repairing

public extension RuleSet {
    /// Why a rule set cannot be written.
    ///
    /// Carries the offending names rather than a sentence, so the message can be
    /// worded where it is shown.
    struct Unusable: Error, Hashable, Sendable {
        /// The names that cannot be folders, in rule-set order. The fallback's
        /// name appears last when it is one of them.
        public let names: [String]

        public init(names: [String]) {
            self.names = names
        }
    }

    /// This rule set, or an error naming what makes it unwritable.
    ///
    /// The check lives here rather than in the app target for the reason this
    /// project keeps rediscovering: a rule in the app target is a rule nobody
    /// can test. `AppState` has no test target by design, so a guard written
    /// there survives being mutated to a no-op and proves nothing.
    func validated() throws -> RuleSet {
        let unusable = problems.compactMap { problem -> String? in
            guard case let .unusableName(_, name, _) = problem else { return nil }
            return name
        }
        guard unusable.isEmpty else { throw Unusable(names: unusable) }
        return self
    }

    /// The nearest usable rule set to this one, for a file that parsed but says
    /// something Ledge must not act on.
    ///
    /// A hand-edited `rules.json` can hold a category with a blank name, or a
    /// `..` fallback. Nothing rejects it on the way in, and `Categorizer`
    /// appends whatever it finds as a path component — so a blank name files
    /// every match straight back into the folder it came from, and `..` files
    /// into the parent, quietly, on every download from then on.
    ///
    /// The repair is the smallest one that removes the hazard. An unusable
    /// category is dropped, not renamed: its extensions fall through to the
    /// next rule that claims them, or to the fallback, which is a defined
    /// outcome the user can see in the editor. The fallback itself cannot be
    /// dropped — something has to catch unmatched files — so an unusable one
    /// reverts to the default name.
    ///
    /// Deliberately *not* "quarantine the file and load the defaults", which is
    /// what an unparseable file gets. That file cannot be read at all; this one
    /// can, and throwing away every rule the user wrote because one name is
    /// blank is a far larger loss than the one being repaired.
    func sanitized() -> RuleSet {
        var repaired = self
        repaired.categories = categories.filter { Category.isUsableFolderName($0.name) }
        if !Category.isUsableFolderName(fallbackName) {
            repaired.fallbackName = RuleSet.defaults.fallbackName
        }
        return repaired
    }
}
