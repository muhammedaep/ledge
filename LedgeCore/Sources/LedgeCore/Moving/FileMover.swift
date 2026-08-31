import Foundation

public enum MoveError: Error {
    case sourceMissing(URL)
    case destinationNotWritable(URL)
    /// Wraps an `NSError` from a failed filesystem operation that wasn't one
    /// of the cases above. `domain`/`code` are preserved (rather than
    /// collapsing straight to `localizedDescription`) so callers — and
    /// `move(_:into:)`'s own collision-retry logic — can tell a lost
    /// name-collision race apart from a disk-full or permission failure.
    /// `description` is kept only for logging/display.
    case underlying(domain: String, code: Int, description: String)
}

extension MoveError: Equatable {
    public static func == (lhs: MoveError, rhs: MoveError) -> Bool {
        switch (lhs, rhs) {
        case let (.sourceMissing(a), .sourceMissing(b)):
            return a == b
        case let (.destinationNotWritable(a), .destinationNotWritable(b)):
            return a == b
        case let (.underlying(d1, c1, _), .underlying(d2, c2, _)):
            // Equality intentionally ignores `description`: it's a
            // locale-dependent display string, not part of the error's identity.
            return d1 == d2 && c1 == c2
        default:
            return false
        }
    }
}

/// The only component that mutates the filesystem.
///
/// Invariant: this never overwrites anything. On a name collision it inserts
/// " (1)", " (2)", … before the extension. Undo relies on the same guarantee,
/// so undoing into a folder that has since gained a same-named file is safe.
public struct FileMover: Sendable {
    /// Bound on retries after a lost name-collision race (see `move(_:into:)`).
    /// Small and fixed: enough to absorb contention against something outside
    /// this process (Finder, another app) without spinning forever on a
    /// genuinely stuck destination.
    ///
    /// `internal` rather than `private` only so the retry tests can assert the
    /// loop honours *this* bound rather than a number copied into the test.
    static let maxCollisionRetries = 5

    /// Serializes the "pick a free name, then move onto it" critical section
    /// across every `FileMover` in this process.
    ///
    /// `availableURL`'s existence check and `moveItem`'s rename aren't one
    /// atomic operation. Empirically, `moveItem` does not reliably surface
    /// that gap as an error under real concurrency: when the folder watcher
    /// and an Organize Now pass (or two Organize Now batches) target the same
    /// destination name at the same moment, both can see the name as free and
    /// both `moveItem` calls can succeed, with the second silently replacing
    /// the first — a genuine overwrite, not merely a thrown error. A retry
    /// alone cannot close that gap because nothing throws to retry on. Since
    /// this app already funnels every filesystem mutation through `FileMover`,
    /// serializing the critical section here removes the race for every
    /// in-process caller: only one `move(_:into:)` computes and acts on a
    /// destination name at a time, so every other caller always sees the true,
    /// up-to-date folder contents. The bounded retry below then remains as a
    /// second line of defense against a collision from outside this process.
    private static let criticalSection = NSLock()

    /// Performs the rename itself. Defaults to the real filesystem and only
    /// needs overriding in tests: the retry loop below exists for a collision
    /// arriving from *outside* this process, and the lock above guarantees no
    /// in-process caller can ever produce one — so a test that does not stand
    /// in for the rename cannot reach the retry at all. Injecting it also makes
    /// the lock's own race a certainty rather than a scheduling accident.
    private let performMove: @Sendable (URL, URL) throws -> Void

    public init(
        performMove: @escaping @Sendable (URL, URL) throws -> Void = {
            try FileManager.default.moveItem(at: $0, to: $1)
        }
    ) {
        self.performMove = performMove
    }

    @discardableResult
    public func move(_ source: URL, into folder: URL) throws -> URL {
        let fm = FileManager.default

        var isDirectoryRef: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectoryRef) else {
            throw MoveError.sourceMissing(source)
        }
        let sourceIsDirectory = isDirectoryRef.boolValue

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw MoveError.destinationNotWritable(folder)
        }

        Self.criticalSection.lock()
        defer { Self.criticalSection.unlock() }

        var attempt = 0
        while true {
            let target = Self.availableURL(for: source.lastPathComponent, in: folder)

            do {
                try performMove(source, target)
            } catch {
                let nsError = error as NSError
                attempt += 1
                if Self.isNameCollision(nsError) && attempt <= Self.maxCollisionRetries {
                    continue
                }
                throw MoveError.underlying(
                    domain: nsError.domain, code: nsError.code, description: nsError.localizedDescription)
            }

            // `URL.appendingPathComponent(_:)` consults the filesystem when no
            // `isDirectory` hint is given, so once the move lands, any URL a
            // caller builds the same way for this path resolves with a trailing
            // slash for a directory. Match that here so callers can compare the
            // returned URL for equality against one they construct themselves.
            return URL(fileURLWithPath: target.path, isDirectory: sourceIsDirectory)
        }
    }

    /// Whether `error` is `moveItem` refusing to clobber an existing item at
    /// the destination, as opposed to an unrelated failure (disk full,
    /// permission denied, …) that a retry can't fix.
    ///
    /// `internal` rather than `private` so it can be pinned directly: it is a
    /// pure function, and broadening it to "any Cocoa error" would silently
    /// turn a disk-full failure into six doomed retries.
    static func isNameCollision(_ error: NSError) -> Bool {
        error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileWriteFileExists.rawValue
    }

    /// Whether *any* directory entry sits at `path` — including a symlink whose
    /// target is gone.
    ///
    /// `FileManager.fileExists` resolves symlinks, so it answers `false` for a
    /// dangling link. `moveItem` does not agree: the link is still an entry in
    /// the folder, so it refuses the same path with `fileWriteFileExists`. Asked
    /// via `fileExists`, `availableURL` therefore hands back a name the move
    /// rejects — and because the name is recomputed identically on every pass,
    /// the collision retry burns all five attempts on it and the item is left
    /// unfileable until someone deletes the link by hand. Measured, not
    /// theorised: a dangling link named `report.pdf` in the destination makes
    /// `fileExists` report false, `lstat` report true, and `moveItem` fail with
    /// Cocoa error 516.
    ///
    /// It also matters to Organize Now, where the plan is shown to the user
    /// before anything moves: a preview must not offer a name the move will
    /// refuse.
    ///
    /// `lstat` rather than a Foundation call because its contract is explicit
    /// about not following the final link, which is the whole point here.
    static func entryExists(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// The first free name in `folder` based on `name`.
    ///
    /// "Free" means no directory entry of any kind — see `entryExists`. A
    /// dangling symlink is left alone rather than clobbered, which is the same
    /// promise this type makes about every other item it finds in its way.
    public static func availableURL(for name: String, in folder: URL) -> URL {
        let candidate = folder.appendingPathComponent(name)
        guard entryExists(atPath: candidate.path) else { return candidate }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension

        var counter = 1
        while true {
            let numbered = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            let url = folder.appendingPathComponent(numbered)
            if !entryExists(atPath: url.path) { return url }
            counter += 1
        }
    }
}
