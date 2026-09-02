import AppKit
import SwiftUI
import LedgeCore

/// The one-pass cleanup for a folder that is already a mess, with a preview
/// shown before anything moves.
///
/// This is the only screen where a single click moves hundreds of files, so the
/// preview is the consent surface: whatever it says will happen has to be what
/// the user is agreeing to. Two consequences run through everything below.
///
/// **It shows each move's source name and its destination, never the
/// destination filename.** The final name of a moved file is chosen inside
/// `FileMover`'s lock at the moment of the move, and `availableURL` is not
/// called under that lock when the preview is built — so between this list
/// being computed and the user pressing Move, the watcher can file something
/// into the same folder under the same name and take the name this sheet
/// would have promised. `FileMover` still never overwrites, so nothing is
/// lost; it just picks `report (1).pdf` instead. A source name is already
/// sitting on disk under it, and a destination folder is chosen by
/// `Categorizer` with no filesystem read — properties of the plan itself that
/// no concurrent filing can falsify. A destination *filename* would be a
/// guess dressed up as a promise.
///
/// **A folder is one unit.** `ScanEngine` reads a folder at depth 1 and never
/// descends, so a project folder is a single `PlannedMove` and moves whole or
/// not at all. `PlannedMove.isFolder` says so on its own row, because a
/// destination name alone cannot tell the user whether "HEIC" means one file
/// or a folder full of them.
struct OrganizeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var folder: URL?
    @State private var preview = OrganizePreview(plan: [])
    @State private var excluded: Set<String> = []
    @State private var isScanning = false

    /// This sheet's own window, so the refresh below can tell its panel becoming
    /// key from Settings becoming key.
    @State private var sheetWindow: NSWindow?

    /// Bumped to ask for a fresh plan. Driving the scan through `.task(id:)`
    /// rather than calling it directly means SwiftUI cancels an in-flight scan
    /// when a newer one is requested, so a slow scan of the folder the user just
    /// navigated away from cannot land on top of a newer result.
    @State private var rescanToken = 0

    private var targetFolder: URL? {
        folder ?? state.preferences.watchedFolders.first
    }

    /// Whether a batch is running. Read from `AppState`, not held here: the
    /// batch outlives this window, so a flag scoped to the view would come back
    /// `false` on reopen and let a second pass start over a folder the first is
    /// still moving through.
    private var isMoving: Bool { state.isOrganizing }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            errorBanner
            content
            Divider()
            footer
        }
        .frame(width: 460)
        .background(WindowReader { sheetWindow = $0 })
        .task(id: rescanToken) { await rescan() }
        // A stale failure from the watcher an hour ago would otherwise be read
        // as this batch's, since `lastError` holds until something clears it.
        .onAppear { state.clearError() }
        // The plan has to be re-read when this sheet is shown again, and
        // `.onAppear`/`.task` are not enough on their own. Measured on macOS
        // 26.6: dismissing the menu bar panel while this sheet is up hides both
        // and *keeps them alive* — the same view instance, its `@State` intact —
        // and reopening the panel restores the sheet without firing `.onAppear`
        // or `.task` a second time. A plan computed once would sit there frozen
        // while the watcher kept filing underneath it. `didBecomeKey` does fire
        // on that reopen, which makes it the trigger that actually works. It is
        // the same technique, for the same reason, as `ShelfView`'s row refresh.
        //
        // Filtered to this sheet and the panel it hangs off, because the
        // notification is global: unfiltered, opening Settings or clicking back
        // into any other window of the app kicks off a full rescan of the
        // watched folder, which is the 132 ms read described on `rescan`.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { note in
            guard let becameKey = note.object as? NSWindow,
                  becameKey === sheetWindow || becameKey === sheetWindow?.sheetParent
            else { return }
            rescanToken += 1
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Organize Now").titleText()

            Text("\(preview.plan.count) items would move. Folders move whole — Ledge never files their contents.")
                .rowMeta()
                .fixedSize(horizontal: false, vertical: true)

            if let target = targetFolder {
                Picker("Folder", selection: Binding(
                    get: { target },
                    set: { newFolder in
                        folder = newFolder
                        // Exclusions name categories in *this* folder's plan.
                        // Carried across, one for a category the new folder has
                        // no row for would be an invisible rule with nothing on
                        // screen to explain it.
                        excluded = []
                        rescanToken += 1
                    }
                )) {
                    ForEach(state.preferences.watchedFolders, id: \.self) { url in
                        Text(url.lastPathComponent).tag(url)
                    }
                }
                .labelsHidden()
                .disabled(isMoving)
            }
        }
        .padding(14)
    }

    @ViewBuilder
    private var content: some View {
        if state.preferences.watchedFolders.isEmpty {
            message("Add a folder to watch in Settings first.")
        } else if let target = targetFolder, !state.isUsable(target) {
            // The gate that used to sit on the shelf's Organize Now button,
            // where it was asked about every watched folder at once. It belongs
            // here, on the one folder the picker has selected — and it has to
            // say *this*, because `ScanEngine` returns an empty plan for a
            // folder it could not read, which the branch below would report as
            // "Nothing left to organize": a folder that was never looked at,
            // described as already tidy.
            message(state.folderStatus[target] == .unreadable
                    ? "Ledge doesn't have permission to read this folder."
                    : "This folder isn't available right now.")
        } else if preview.isEmpty {
            message(isScanning
                    ? "Looking through this folder…"
                    : "Nothing left to organize in this folder.")
        } else {
            List {
                ForEach(preview.groups) { group in
                    Section {
                        // `preview.plan` is already ordered by filename;
                        // filtering it keeps that order rather than
                        // re-deriving it per section.
                        ForEach(preview.plan.filter { $0.destination.category == group.category }) { item in
                            HStack(spacing: 8) {
                                Text(item.source.lastPathComponent)
                                    .fieldText()
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer(minLength: 12)
                                Text(destinationLabel(for: item))
                                    .rowMeta()
                                    .lineLimit(1)
                            }
                        }
                    } header: {
                        Toggle(isOn: binding(for: group.category)) {
                            HStack {
                                Text(group.category)
                                Spacer()
                                Text("\(group.count)")
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .disabled(isMoving)
                    }
                }
            }
            .frame(height: 260)
        }
    }

    /// Where one planned move lands, said the way the shelf says it.
    ///
    /// A folder is named as a whole rather than given a destination trail,
    /// because Ledge never looks inside one and a trail would imply it had.
    /// Says only "whole folder", not the category — the row already sits
    /// inside that category's section, so repeating its name here would
    /// just echo the `Toggle` header above it.
    private func destinationLabel(for item: PlannedMove) -> String {
        item.isFolder
            ? String(localized: "whole folder")
            : item.destination.folder.lastPathComponent
    }

    private var footer: some View {
        HStack {
            // Offered only when the batch actually moved something.
            // `UndoService.undoBatch` finds no records for a batch where every
            // move failed and returns quietly, so the button would report
            // success having put nothing back. Until there is one, the
            // reassurance the design gives before the fact stands in its place.
            if let outcome = state.lastOrganizeOutcome, outcome.isUndoable {
                Button("Undo Last Batch") { undo(outcome.id) }
                    .disabled(isMoving)
            } else {
                Text("One undo restores the whole batch")
                    .rowMeta()
            }
            outcomeSummary
            Spacer()
            // Never disabled, and it does not stop the batch — it closes the
            // preview. The label says so while one is running: a button reading
            // "Cancel" next to "Moving…" promises an abort this does not
            // perform. Trapping the user in the sheet for a batch that may be
            // copying gigabytes across volumes would be worse, and it is a
            // promise the app cannot keep anyway — clicking the menu bar icon
            // hides the panel regardless. Nothing is lost by leaving: the batch
            // and its undo handle live on `AppState` now, and are still here
            // when the sheet is reopened.
            Button(isMoving ? "Close" : "Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(action: startMove) { Text(moveButtonTitle) }
                .keyboardShortcut(.defaultAction)
                .disabled(movableCount == 0 || isMoving)
        }
        .padding(12)
    }

    /// What the last batch actually did. The button promised a number before it
    /// ran; this is the number that landed, and they are allowed to differ — a
    /// source can be filed away by the watcher or deleted between the two.
    @ViewBuilder
    private var outcomeSummary: some View {
        if let outcome = state.lastOrganizeOutcome, !isMoving {
            Text(outcome.isPartial
                 ? "Moved \(outcome.moved) of \(outcome.attempted)."
                 : "Moved \(outcome.moved).")
                .rowMeta()
                .padding(.leading, 4)
        }
    }

    /// A failed move would otherwise be invisible here: `AppState` records it in
    /// `lastError`, but the only thing that renders that is the shelf, and this
    /// sheet is sitting on top of the shelf. A batch that silently moved fewer
    /// files than the button promised is exactly the kind of lie this screen
    /// cannot afford.
    private var errorBanner: some View {
        ErrorBanner(message: state.lastError, horizontalPadding: 14, topPadding: 10,
                    action: state.lastErrorOffersPrivacySettings
                        ? (String(localized: "Open Privacy Settings"), { PrivacySettings.open() })
                        : nil) {
            state.clearError()
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    /// Every planned move the button promises, with the categories still
    /// switched on — including the fallback. The boards count unclaimed
    /// files out of the button because they leave them in place; Ledge
    /// moves them, so a fallback left on counts them too (spec §8.1).
    private var movableCount: Int { preview.selectedCount(excluding: excluded) }

    private var moveButtonTitle: LocalizedStringKey {
        isMoving ? "Moving…" : "Move \(movableCount) Items"
    }

    // MARK: - Actions

    private func binding(for category: String) -> Binding<Bool> {
        Binding(
            get: { !excluded.contains(category) },
            set: { isOn in
                if isOn {
                    excluded.remove(category)
                } else {
                    excluded.insert(category)
                }
            }
        )
    }

    /// `moves` is captured before the batch starts, so what runs is the list the
    /// user was looking at when they agreed to it — not whatever a rescan
    /// landing mid-batch might have replaced it with.
    ///
    /// The flag and the resulting batch both live on `AppState`, so this task
    /// finishes correctly even if the sheet is dismissed while it runs.
    private func startMove() {
        guard let root = targetFolder else { return }
        let moves = preview.selectedMoves(excluding: excluded)
        Task {
            await state.apply(moves, root: root)
            rescanToken += 1
        }
    }

    private func undo(_ batch: UUID) {
        Task {
            await state.undoBatch(batch)
            rescanToken += 1
        }
    }

    /// Off the main actor, unlike the rest of this view.
    ///
    /// The plan is only a read, but it is a `contentsOfDirectory` plus a
    /// `resourceValues` per entry, and the folder this feature exists for held
    /// 1,504 items. Measured on that shape — 1,524 entries, release build, warm
    /// cache, local SSD — `ScanEngine.plan` takes a median of 132 ms and as much
    /// as 203 ms. On the main actor that is a visible stall every time the sheet
    /// refreshes, and worse on a cold cache or an external volume. The scan
    /// itself is pure and takes only `Sendable` values, so moving it costs
    /// nothing.
    private func rescan() async {
        // Never re-plan mid-batch: the folder is being emptied underneath us,
        // and the result would describe a state that exists only halfway
        // through. The batch's own completion asks for a fresh plan.
        guard !isMoving, let target = targetFolder else { return }
        folder = target

        let rules = state.rules
        isScanning = true
        defer { isScanning = false }

        let plan = await Task.detached(priority: .userInitiated) {
            ScanEngine.plan(folder: target, using: rules)
        }.value

        // A newer scan was requested while this one ran; its result wins.
        guard !Task.isCancelled else { return }
        preview = OrganizePreview(plan: plan)
    }
}

