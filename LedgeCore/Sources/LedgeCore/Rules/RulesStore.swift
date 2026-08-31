import Foundation

/// Loads and saves the rule set as JSON. A corrupt file is moved aside rather
/// than deleted, so a user who hand-edited it can get their work back.
public final class RulesStore {
    private let directory: URL
    private let fileName = "rules.json"

    public private(set) var lastLoadWasCorrupt = false

    /// True when the last load read a file that parsed but held a rule Ledge
    /// must not act on, and repaired it. Distinct from `lastLoadWasCorrupt`:
    /// nothing was quarantined and most of the user's rules survived.
    public private(set) var lastLoadWasRepaired = false

    public init(directory: URL) {
        self.directory = directory
    }

    /// The app's real location. See `LedgeSupportDirectory`.
    public static func applicationSupport() -> RulesStore {
        RulesStore(directory: LedgeSupportDirectory.url)
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    public func load() -> RuleSet {
        lastLoadWasCorrupt = false
        lastLoadWasRepaired = false
        guard let data = try? Data(contentsOf: fileURL) else { return .defaults }

        do {
            // Parsing is not the same as being usable. A hand-edited file can
            // decode perfectly and still name a category "" or "..", which
            // `Categorizer` would append as a path component — filing every
            // match back into the folder it came from, or into the parent.
            // Nothing downstream checks, so the check belongs on the way in.
            let decoded = try JSONDecoder().decode(RuleSet.self, from: data)
            let sanitized = decoded.sanitized()
            lastLoadWasRepaired = sanitized != decoded
            return sanitized
        } catch {
            lastLoadWasCorrupt = true
            quarantine()
            return .defaults
        }
    }

    /// Writes the rule set, refusing one that names a folder Ledge must not
    /// file into. The refusal is here rather than only at the caller because
    /// this is the boundary every future caller has to come through.
    public func save(_ rules: RuleSet) throws {
        let rules = try rules.validated()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // `.atomic` is deliberate and cannot be unit-tested away: proving it
        // matters needs a crash mid-write. Without it an interrupted save
        // leaves a truncated rules.json, which loads as corrupt and sends the
        // user's rules to quarantine. Do not "simplify" it.
        try encoder.encode(rules).write(to: fileURL, options: .atomic)
    }

    /// Moves the unreadable file aside under a timestamped name.
    ///
    /// The stamp has second resolution, so two corrupt loads inside the same
    /// second name the same target. Going through `FileMover.availableURL`
    /// rather than using that name directly is what stops the second rename
    /// from failing into the `try?` below and leaving the corrupt `rules.json`
    /// in place — where the next `save` would overwrite the very hand edits
    /// quarantining exists to preserve.
    private func quarantine() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let target = FileMover.availableURL(for: "rules.corrupt-\(stamp).json", in: directory)
        try? FileManager.default.moveItem(at: fileURL, to: target)
    }
}
