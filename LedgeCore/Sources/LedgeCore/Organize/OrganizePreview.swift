import Foundation

/// What the Organize Now preview shows, and exactly which moves the user's
/// confirmation acts on.
///
/// Both answers are derived here from one plan, so the number printed beside a
/// category and the moves performed for that category cannot drift apart.
/// Computing them separately in the view is what would let them: this is the
/// one screen where a single click moves hundreds of files, and a preview that
/// promises a count the move does not honour is worse than no preview at all.
public struct OrganizePreview: Equatable, Sendable {
    /// One row of the preview: a category and how many items are bound for it.
    ///
    /// Deliberately a category and a count, never a destination filename. The
    /// final name is chosen inside `FileMover`'s lock at the moment of the move,
    /// and between this preview being computed and the user pressing Move the
    /// watcher may have filed something into the same folder under the same
    /// name — so any name shown here would be a guess that the move is free to
    /// break. A category and a count are properties of the plan itself, they
    /// are what the toggles select, and they stay true.
    public struct Group: Identifiable, Equatable, Sendable {
        public let category: String
        public let count: Int

        public var id: String { category }

        public init(category: String, count: Int) {
            self.category = category
            self.count = count
        }
    }

    public let plan: [PlannedMove]

    public init(plan: [PlannedMove]) {
        self.plan = plan
    }

    /// The rows to show, largest first.
    ///
    /// Ties break on the category name. `sorted(by:)` is not guaranteed stable,
    /// so ordering on the count alone lets two equal-sized categories swap
    /// places between one rescan and the next — a list reshuffling under the
    /// user while they are deciding what to move.
    public var groups: [Group] {
        Dictionary(grouping: plan, by: \.destination.category)
            .map { Group(category: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.category < $1.category : $0.count > $1.count }
    }

    public var isEmpty: Bool { plan.isEmpty }

    /// The moves a confirmation acts on, given the categories switched off.
    ///
    /// The counterpart of `groups`: every move counted in a group that is not
    /// excluded appears here, and nothing else does.
    public func selectedMoves(excluding excluded: Set<String>) -> [PlannedMove] {
        plan.filter { !excluded.contains($0.destination.category) }
    }

    /// How many items the confirmation button promises to move.
    public func selectedCount(excluding excluded: Set<String>) -> Int {
        selectedMoves(excluding: excluded).count
    }
}
