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

    /// The app's real location: ~/Library/Application Support/Ledge
    public static func applicationSupport() -> RulesStore {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
        return RulesStore(directory: base)
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
        try encoder.encode(rules).write(to: fileURL, options: .atomic)
    }

    private func quarantine() {
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let target = directory.appendingPathComponent("rules.corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: fileURL, to: target)
    }
}
