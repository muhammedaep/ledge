import Foundation

/// A depth-1 listing of a folder. Diffing two of these is how the watcher
/// decides what is new, and keeping it separate from the event plumbing means
/// the decision is testable without any timing.
public struct DirectorySnapshot: Equatable, Sendable {
    public let entries: Set<URL>

    public init(entries: Set<URL>) {
        self.entries = entries
    }

    /// `.skipsSubdirectoryDescendants` is documentation of intent, not a
    /// behavioural request: `contentsOfDirectory` is shallow either way (the
    /// option only means anything to `enumerator(at:)`), so removing it changes
    /// nothing and no test can guard it. It stays as a signpost for anyone
    /// tempted to swap in an enumerator, which `scanningReadsTopLevelEntriesOnly`
    /// would then catch.
    ///
    /// `.resolvingSymlinksInPath()` on the *folder* is the opposite —
    /// load-bearing. `entries` is a `Set<URL>` and `URL` equality is
    /// path-string equality, so a snapshot is only diffable against one taken
    /// elsewhere if both sides normalize; `/var/…` and `/private/var/…` are
    /// otherwise two different keys for one file.
    /// `newEntriesFromTwoRealScansOfTheSameFolder` guards it.
    ///
    /// On the folder and *only* the folder. Until 2026-09-03 every entry was
    /// resolved, which looked like the same thing and was not: it resolves the
    /// leaf too, so a symlink in the watched folder came back as its target's
    /// path and the app filed the target — a file it had never been pointed
    /// at, anywhere on disk, delivered by nothing more than an archive with a
    /// link in it. A link is an entry of the folder it sits in; the mover
    /// already treats it as one, and now the scan does too.
    /// `aLeafSymlinkIsReportedAtItsOwnPathNotItsTargets` guards it.
    public init(scanning folder: URL) {
        let base = folder.resolvingSymlinksInPath()
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: base,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        self.entries = Set(contents.map { base.appendingPathComponent($0.lastPathComponent) })
    }

    public func newEntries(comparedTo other: DirectorySnapshot) -> Set<URL> {
        entries.subtracting(other.entries)
    }
}
