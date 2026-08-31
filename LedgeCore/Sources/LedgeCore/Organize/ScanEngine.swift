import Foundation

public struct PlannedMove: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: URL
    public let destination: Destination

    public init(id: UUID = UUID(), source: URL, destination: Destination) {
        self.id = id
        self.source = source
        self.destination = destination
    }
}

/// Builds a dry-run plan for an already-messy folder. Reads only — nothing
/// moves until the user confirms the preview.
public enum ScanEngine {
    /// `factsProvider` defaults to the real filesystem and only needs
    /// overriding in tests: it lets a vanished entry (deleted between the
    /// directory listing and this per-entry read — a cancelled download, or
    /// the user deleting something mid-preview) be simulated deterministically
    /// instead of raced against a real deletion.
    public static func plan(
        folder: URL,
        using rules: RuleSet,
        factsProvider: (URL) -> FileFacts? = { FileFacts(url: $0) }
    ) -> [PlannedMove] {
        let snapshot = DirectorySnapshot(scanning: folder)

        // A folder that is itself a destination must not be filed into itself.
        var reserved = Set(rules.categories.map(\.name))
        reserved.insert(rules.fallbackName)

        return snapshot.entries
            .filter { !reserved.contains($0.lastPathComponent) }
            .compactMap { url -> PlannedMove? in
                guard let facts = factsProvider(url) else { return nil }
                let destination = Categorizer.destination(for: facts, in: folder, using: rules)
                return PlannedMove(source: url, destination: destination)
            }
            .sorted { $0.source.lastPathComponent < $1.source.lastPathComponent }
    }
}
