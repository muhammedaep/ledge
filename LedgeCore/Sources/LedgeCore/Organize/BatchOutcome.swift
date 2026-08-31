import Foundation

/// How an Organize Now batch actually went.
///
/// The preview promises a count before the batch runs. This is the counterpart
/// afterwards, and it exists because those two numbers can differ: between the
/// plan being shown and the moves being made, a source can be filed away by the
/// watcher or deleted by the user, and `FileMover` then refuses it. A batch that
/// quietly moved fewer files than the button promised is the same kind of lie
/// the preview is built to avoid, so the count that actually landed is carried
/// out of the batch rather than inferred from it.
public struct BatchOutcome: Equatable, Sendable, Identifiable {
    public let id: UUID
    /// How many moves succeeded.
    public let moved: Int
    /// How many were attempted — the number the button promised.
    public let attempted: Int

    public init(id: UUID, moved: Int, attempted: Int) {
        self.id = id
        self.moved = moved
        self.attempted = attempted
    }

    /// Whether there is anything for "Undo Last Batch" to undo.
    ///
    /// A batch where every move failed writes no journal records, so
    /// `UndoService.undoBatch` finds nothing and returns without error or
    /// effect. Offering the button anyway gives the user a control that reports
    /// success and does nothing — worse than not offering it, because it implies
    /// something was put back.
    public var isUndoable: Bool { moved > 0 }

    /// True when fewer moves landed than were attempted, so the user is told
    /// rather than left to compare two numbers themselves.
    public var isPartial: Bool { moved < attempted }
}
