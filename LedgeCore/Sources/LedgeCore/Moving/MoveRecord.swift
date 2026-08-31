import Foundation

/// One completed move. `from` is the folder the file was found in, which is
/// what undo puts it back into.
public struct MoveRecord: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public let originalName: String
    public let from: URL
    public let to: URL
    public let date: Date
    /// Set for Organize Now batches so they undo as one action; nil for automatic moves.
    public let batchID: UUID?

    public init(
        id: UUID = UUID(),
        originalName: String,
        from: URL,
        to: URL,
        date: Date = Date(),
        batchID: UUID? = nil
    ) {
        self.id = id
        self.originalName = originalName
        self.from = from
        self.to = to
        self.date = date
        self.batchID = batchID
    }
}
