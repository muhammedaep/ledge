import Foundation

/// When two URLs name the same directory, and whether Ledge can use it.
///
/// Both questions were being answered in two places with two different answers.
/// Projects collapsed `/tmp/x`, `/tmp/x/`, `/private/tmp/x` and `..`-relative
/// spellings to one folder; watched folders compared raw `URL` equality, so the
/// same directory could be added twice and get two `O_EVTONLY` descriptors on
/// one vnode, reporting every new file twice. The rule belongs in one tested
/// place rather than in whichever caller remembered it.
public enum FolderIdentity {
    /// The key two URLs share exactly when they name the same directory.
    ///
    /// The symlink case is not hypothetical on macOS — `/tmp` and `/var` are
    /// symlinks into `/private`, and an open panel can hand back either form.
    ///
    /// `resolvingSymlinksInPath()` reads the filesystem, and — measured, not
    /// assumed; the tests pin it — leaves a path it cannot walk exactly as it
    /// found it rather than resolving the existing prefix. So two *different*
    /// spellings of a folder that is gone do not compare equal.
    ///
    /// What makes that survivable is *when* the resolution happens, not where
    /// the URLs are stored. Callers store the URL they were handed — the open
    /// panel's, verbatim — and this resolves at comparison time. So the
    /// comparison that matters, "is this folder already in the list", is made
    /// while the user is picking a folder that by definition exists, and both
    /// sides resolve then. The stored spellings never have to agree.
    ///
    /// A folder that has been deleted or unmounted still compares equal to
    /// itself, which is what keeps it from being duplicated while it is away.
    public static func key(_ folder: URL) -> String {
        folder.standardizedFileURL.resolvingSymlinksInPath().path
    }

    /// Whether two URLs name the same directory.
    public static func sameFolder(_ one: URL, _ other: URL) -> Bool {
        key(one) == key(other)
    }

    /// Whether `folder` is already in `folders`, by identity rather than by
    /// spelling.
    public static func contains(_ folders: [URL], _ folder: URL) -> Bool {
        let wanted = key(folder)
        return folders.contains { key($0) == wanted }
    }

    /// `folders` with every spelling of `folder` removed.
    public static func removing(_ folder: URL, from folders: [URL]) -> [URL] {
        let unwanted = key(folder)
        return folders.filter { key($0) != unwanted }
    }

    /// `folders` with `folder` appended unless it is already there. Returns the
    /// list unchanged when it is, so a caller cannot append a duplicate by
    /// forgetting to check.
    public static func adding(_ folder: URL, to folders: [URL]) -> [URL] {
        contains(folders, folder) ? folders : folders + [folder]
    }
}

/// Whether a folder can be watched, and if not, which kind of "not".
///
/// The distinction is the whole point. A folder that is *missing* — an ejected
/// drive, a deleted directory — is not a permission problem, and presenting it
/// as one strands the user in front of a consent dialog that cannot grant
/// anything, for a folder that is not there to be granted.
public enum FolderAccess: Equatable, Sendable {
    /// It is there and its contents can be listed.
    case readable
    /// No such directory. Nothing to grant; the folder is gone or its volume is
    /// unmounted.
    case missing
    /// It exists but its contents cannot be listed — on macOS, a declined or
    /// never-granted TCC prompt for a protected folder such as `~/Downloads`.
    case unreadable

    /// Classifies `folder` by asking the filesystem.
    ///
    /// `fileExists` is what separates the two failures: TCC gates *reading a
    /// protected folder's contents*, not knowing that it exists, so a blocked
    /// folder answers true here and then fails the listing, while a missing one
    /// fails at the first step.
    ///
    /// This does real I/O — a listing, which is `O(entries)`, and on an
    /// unmounted volume blocks for the mount timeout. Never call it on the main
    /// actor.
    public static func of(_ folder: URL, using fileManager: FileManager = .default) -> FolderAccess {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return .missing }

        return (try? fileManager.contentsOfDirectory(atPath: folder.path)) == nil
            ? .unreadable
            : .readable
    }
}
