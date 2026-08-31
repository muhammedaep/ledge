import Foundation

/// The two questions this app asks the filesystem about a path, kept apart on
/// purpose because they have different answers and the difference bites.
///
/// `FileManager.fileExists` answers *both* of them at once, and follows
/// symlinks doing it. That conflation is what put five callers on the wrong
/// side of a dangling link: `FileMover` had already worked out that "is an
/// entry here" needs `lstat`, but the rule lived as a private helper on the
/// mover, so `UndoService`, the shelf and `AppState` each reached for
/// `fileExists` and got the other answer. A record pointing at a dangling link
/// reported as gone when it was not.
///
/// One place, one implementation, tested — the same reason `FolderIdentity`
/// exists.
public enum FileEntry {
    /// Whether *any* directory entry sits at `path`, including a symlink whose
    /// target is gone.
    ///
    /// `FileManager.fileExists` resolves symlinks, so it answers `false` for a
    /// dangling link. `moveItem` does not agree: the link is still an entry in
    /// the folder, so it refuses the same path with `fileWriteFileExists` — and
    /// moves the link itself without complaint when asked to. Measured, not
    /// theorised: a dangling link named `report.pdf` makes `fileExists` report
    /// false, `lstat` report true, `moveItem` fail with Cocoa error 516 when it
    /// is the destination, and succeed when it is the source.
    ///
    /// That gap is load-bearing in three places. `FileMover.availableURL` would
    /// otherwise hand back a name the move rejects, and because the name is
    /// recomputed identically on every pass, the collision retry burns all five
    /// attempts on it and the item is left unfileable until someone deletes the
    /// link by hand. `FileMover.move` would call an entry it can move
    /// `sourceMissing`. And undo would refuse to put a file back that is
    /// sitting exactly where the journal says it is.
    ///
    /// It also matters to Organize Now, where the plan is shown to the user
    /// before anything moves: a preview must not offer a name the move will
    /// refuse.
    ///
    /// `lstat` rather than a Foundation call because its contract is explicit
    /// about not following the final link, which is the whole point here.
    public static func exists(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0
    }

    /// Whether `path` leads to a directory, following symlinks.
    ///
    /// Deliberately the *other* notion. A symlink to a folder is a folder you
    /// can file into, so this one has to resolve; a dangling link leads
    /// nowhere, so it is not a directory even though `exists` reports it
    /// present. Both callers want exactly that: `FileMover` uses it only to
    /// build a URL whose trailing slash matches what
    /// `URL.appendingPathComponent(_:)` would produce for the same path, and
    /// `AppState` uses it to ask whether a project folder is still somewhere a
    /// download can land.
    ///
    /// `stat` rather than `lstat` for the same reason `exists` is the reverse:
    /// the following behaviour is the contract, not an accident.
    public static func isDirectory(atPath path: String) -> Bool {
        var info = stat()
        guard stat(path, &info) == 0 else { return false }
        return info.st_mode & S_IFMT == S_IFDIR
    }
}
