import Foundation

/// A depth-1 listing of a folder. Diffing two of these is how the watcher
/// decides what is new, and keeping it separate from the event plumbing means
/// the decision is testable without any timing.
public struct DirectorySnapshot: Equatable, Sendable {
    public let entries: Set<URL>

    public init(entries: Set<URL>) {
        self.entries = entries
    }

    public init(scanning folder: URL) {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        self.entries = Set(contents.map { $0.resolvingSymlinksInPath() })
    }

    public func newEntries(comparedTo other: DirectorySnapshot) -> Set<URL> {
        entries.subtracting(other.entries)
    }
}
