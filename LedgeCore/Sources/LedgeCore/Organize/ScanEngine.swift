import Foundation

public struct PlannedMove: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let source: URL
    public let destination: Destination

    /// Whether this entry is filed as one opaque unit rather than by its
    /// extension — a browsable folder.
    ///
    /// A package (`.app`, `.sketch`) is moved whole too, but it is not a
    /// *folder* to anyone reading the preview: it has an extension, a rule
    /// claims it by that extension, and calling it a folder would say the
    /// opposite of what happened to it.
    public let isFolder: Bool

    public init(id: UUID = UUID(), source: URL, destination: Destination, isFolder: Bool = false) {
        self.id = id
        self.source = source
        self.destination = destination
        self.isFolder = isFolder
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
        let reserved = rules.destinationFolderNames

        return snapshot.entries
            .filter { !reserved.contains($0.lastPathComponent) }
            .compactMap { url -> PlannedMove? in
                guard let facts = factsProvider(url) else { return nil }
                let destination = Categorizer.destination(for: facts, in: folder, using: rules)
                return PlannedMove(source: url,
                                   destination: destination,
                                   isFolder: facts.isDirectory && !facts.isPackage)
            }
            .sorted { $0.source.lastPathComponent < $1.source.lastPathComponent }
    }
}
