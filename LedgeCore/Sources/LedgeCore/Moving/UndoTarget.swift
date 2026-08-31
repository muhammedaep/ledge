import Foundation

/// What a single undo gesture acts on.
///
/// Spec §7.5: "⌘Z in the shelf undoes the most recent record; for an Organize
/// Now batch it undoes the entire `batchID` as one action." That sentence is a
/// rule — it decides between two different filesystem operations on the strength
/// of one nullable field — so it lives here with tests rather than inside a
/// keyboard handler in the app target, where nothing could test it.
///
/// The row buttons do not go through this. `↩` on a row is a request to undo
/// *that* row, batch or not; ⌘Z is a request to undo the last *thing that
/// happened*, and one Organize Now pass is one thing that happened.
public enum UndoTarget: Equatable, Sendable {
    /// Nothing has been filed, so the gesture has nothing to act on. Distinct
    /// from a failure: the caller should be inert, not report an error.
    case nothing
    /// One automatic move.
    case record(MoveRecord)
    /// A whole Organize Now batch, undone as one action.
    case batch(UUID)

    /// What undo acts on, given the shelf's records.
    ///
    /// `records` must be newest first, which is `MoveJournal`'s documented order
    /// and what `AppState.recentRecords` carries through unchanged — it takes a
    /// `prefix`, which preserves it. Pinned by a test against a real journal
    /// rather than trusted, because this reads `first` and a journal that
    /// silently became oldest-first would make ⌘Z undo the wrong end of the
    /// history without failing anything else.
    public static func mostRecent(in records: [MoveRecord]) -> UndoTarget {
        guard let newest = records.first else { return .nothing }
        guard let batchID = newest.batchID else { return .record(newest) }
        return .batch(batchID)
    }
}
