import Testing
import Foundation
@testable import LedgeCore

@Test func aBatchThatMovedSomethingCanBeUndone() {
    #expect(BatchOutcome(id: UUID(), moved: 3, attempted: 3).isUndoable)
    #expect(BatchOutcome(id: UUID(), moved: 1, attempted: 9).isUndoable)
}

@Test func aBatchWhereEveryMoveFailedIsNotUndoable() {
    // Nothing was journalled, so `undoBatch` would find nothing and report
    // success having done nothing.
    #expect(!BatchOutcome(id: UUID(), moved: 0, attempted: 5).isUndoable)
}

@Test func anEmptyBatchIsNotUndoable() {
    #expect(!BatchOutcome(id: UUID(), moved: 0, attempted: 0).isUndoable)
}

@Test func aBatchIsPartialOnlyWhenSomethingWasLeftBehind() {
    #expect(!BatchOutcome(id: UUID(), moved: 4, attempted: 4).isPartial)
    #expect(BatchOutcome(id: UUID(), moved: 3, attempted: 4).isPartial)
    #expect(BatchOutcome(id: UUID(), moved: 0, attempted: 4).isPartial)
    #expect(!BatchOutcome(id: UUID(), moved: 0, attempted: 0).isPartial)
}
