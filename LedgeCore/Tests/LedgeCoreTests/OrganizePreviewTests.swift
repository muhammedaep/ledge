import Testing
import Foundation
@testable import LedgeCore

private func move(_ name: String, _ category: String) -> PlannedMove {
    let root = URL(fileURLWithPath: "/tmp/organize-preview")
    return PlannedMove(
        source: root.appendingPathComponent(name),
        destination: Destination(
            folder: root.appendingPathComponent(category), category: category))
}

// MARK: - The preview must not lie
//
// The count shown beside a category and the moves performed for that category
// are the same claim stated twice. These pin them together.

@Test func everyPlannedMoveIsCountedExactlyOnce() {
    let preview = OrganizePreview(plan: [
        move("a.png", "Images"), move("b.png", "Images"),
        move("c.mp4", "Videos"), move("notes.txt", "Documents")
    ])

    #expect(preview.groups.map(\.count).reduce(0, +) == preview.plan.count)
    #expect(Set(preview.groups.map(\.category)) == ["Images", "Videos", "Documents"])
}

@Test func groupCountMatchesWhatThatCategoryActuallyMoves() {
    let preview = OrganizePreview(plan: [
        move("a.png", "Images"), move("b.png", "Images"),
        move("c.mp4", "Videos")
    ])

    for group in preview.groups {
        // Excluding every other category leaves exactly this group's moves.
        let others = Set(preview.groups.map(\.category)).subtracting([group.category])
        #expect(preview.selectedMoves(excluding: others).count == group.count)
    }
}

@Test func nothingExcludedSelectsTheWholePlan() {
    let preview = OrganizePreview(plan: [
        move("a.png", "Images"), move("c.mp4", "Videos")
    ])

    #expect(preview.selectedMoves(excluding: []) == preview.plan)
    #expect(preview.selectedCount(excluding: []) == 2)
}

@Test func excludingACategoryDropsExactlyItsMoves() {
    let preview = OrganizePreview(plan: [
        move("a.png", "Images"), move("b.png", "Images"),
        move("c.mp4", "Videos")
    ])

    let selected = preview.selectedMoves(excluding: ["Images"])

    #expect(selected.map(\.source.lastPathComponent) == ["c.mp4"])
    #expect(preview.selectedCount(excluding: ["Images"]) == 1)
}

@Test func excludingEverythingSelectsNothing() {
    let preview = OrganizePreview(plan: [move("a.png", "Images"), move("c.mp4", "Videos")])
    #expect(preview.selectedMoves(excluding: ["Images", "Videos"]).isEmpty)
}

@Test func anUnknownExclusionChangesNothing() {
    let preview = OrganizePreview(plan: [move("a.png", "Images")])
    #expect(preview.selectedCount(excluding: ["Fonts"]) == 1)
}

// MARK: - Ordering

@Test func rowsAreLargestFirst() {
    let preview = OrganizePreview(plan: [
        move("c.mp4", "Videos"),
        move("a.png", "Images"), move("b.png", "Images"), move("c.png", "Images"),
        move("x.mp3", "Audio"), move("y.mp3", "Audio")
    ])

    #expect(preview.groups.map(\.category) == ["Images", "Audio", "Videos"])
}

@Test func equalSizedRowsKeepAStableOrderAcrossRescans() {
    // `sorted(by:)` is not stable, so ordering on count alone would let these
    // three swap places between refreshes while the user is reading the list.
    let plan = [move("a.png", "Images"), move("c.mp4", "Videos"), move("n.txt", "Documents")]

    for _ in 0..<50 {
        #expect(OrganizePreview(plan: plan.shuffled()).groups.map(\.category)
                == ["Documents", "Images", "Videos"])
    }
}

@Test func anEmptyPlanHasNoRows() {
    let preview = OrganizePreview(plan: [])
    #expect(preview.isEmpty)
    #expect(preview.groups.isEmpty)
    #expect(preview.selectedCount(excluding: []) == 0)
}

// MARK: - A folder is one unit
//
// `ScanEngine` never descends into a directory, so a project folder is a single
// planned move. The preview must count it as one row entry, not as its contents.

@Test func aFolderCountsAsOneItem() {
    let preview = OrganizePreview(plan: [
        move("a.png", "Images"),
        move("Some Project", "Other")      // a directory, planned whole
    ])

    let other = preview.groups.first { $0.category == "Other" }
    #expect(other?.count == 1)
    #expect(preview.selectedMoves(excluding: ["Images"]).map(\.source.lastPathComponent)
            == ["Some Project"])
}
