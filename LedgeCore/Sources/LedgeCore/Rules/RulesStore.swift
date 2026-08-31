import Foundation

/// Loads and saves the rule set as JSON. A corrupt file is moved aside rather
/// than deleted, so a user who hand-edited it can get their work back.
public final class RulesStore {
    private let directory: URL
    private let fileName = "rules.json"

    public private(set) var lastLoadWasCorrupt = false

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
        guard let data = try? Data(contentsOf: fileURL) else { return .defaults }

        do {
            return try JSONDecoder().decode(RuleSet.self, from: data)
        } catch {
            lastLoadWasCorrupt = true
            quarantine()
            return .defaults
        }
    }

    public func save(_ rules: RuleSet) throws {
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
