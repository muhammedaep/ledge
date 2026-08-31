import Foundation

public enum UndoError: Error, Equatable {
    case fileNoLongerAtRecordedPath(URL)
}

/// Reverses recorded moves. Undo goes through FileMover like every other move,
/// so it inherits the never-overwrite guarantee: if something new has taken the
/// original name, the restored file is numbered instead of clobbering it.
public struct UndoService {
    private let mover: FileMover
    private let journal: MoveJournal

    public init(mover: FileMover, journal: MoveJournal) {
        self.mover = mover
        self.journal = journal
    }

    /// `FileEntry.exists`, not `fileExists`: this is the same "is the file
    /// still there" question `FileMover` answers with `lstat`, and asking it
    /// the other way made undo refuse a dangling symlink that the mover moves
    /// happily — a file the user could see, reported as gone.
    @discardableResult
    public func undo(_ record: MoveRecord) throws -> URL {
        guard FileEntry.exists(atPath: record.to.path) else {
            throw UndoError.fileNoLongerAtRecordedPath(record.to)
        }
        let restored = try mover.move(record.to, into: record.from)
        try journal.remove(id: record.id)
        return restored
    }

    /// Undoes an Organize Now batch as one action. Records whose file has since
    /// gone missing are skipped rather than aborting the whole batch — and,
    /// like `undo(_:)`, a skipped record is left in the journal rather than
    /// dropped, so the user doesn't lose their only trail to a file that was
    /// never actually put back (it stays individually undoable if it later
    /// reappears, e.g. restored from Trash or resynced by iCloud/Dropbox).
    @discardableResult
    public func undoBatch(_ batchID: UUID) throws -> [URL] {
        var restored: [URL] = []
        for record in journal.records(inBatch: batchID) {
            guard FileEntry.exists(atPath: record.to.path) else { continue }
            restored.append(try mover.move(record.to, into: record.from))
            try journal.remove(id: record.id)
        }
        return restored
    }
}
