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
/// **It shows categories and counts, never destination filenames.** The final
/// name of a moved file is chosen inside `FileMover`'s lock at the moment of the
/// move, and `availableURL` is not called under that lock when the preview is
/// built — so between this list being computed and the user pressing Move, the
/// watcher can file something into the same folder under the same name and take
/// the name this sheet would have promised. `FileMover` still never overwrites,
/// so nothing is lost; it just picks `report (1).pdf` instead. A category and a
/// count are properties of the plan itself, they are exactly what the toggles
/// select, and no concurrent filing can falsify them. A filename would be a
/// guess dressed up as a promise.
///
/// **A folder is one unit.** `ScanEngine` reads a folder at depth 1 and never
/// descends, so a project folder is a single `PlannedMove` and moves whole or
/// not at all. The caption says so, because from a count alone the user cannot
/// tell whether "Other 1" means one folder or everything inside it.
struct OrganizeSheet: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var folder: URL?
    @State private var preview = OrganizePreview(plan: [])
    @State private var excluded: Set<String> = []
    @State private var lastBatch: UUID?
    @State private var isScanning = false

    /// True for the whole of a batch — a move or an undo, both of which write to
    /// disk. It disables every button that starts more filing, so a second pass
    /// cannot begin over a folder the first is still moving through.
    @State private var isMoving = false

    /// Bumped to ask for a fresh plan. Driving the scan through `.task(id:)`
    /// rather than calling it directly means SwiftUI cancels an in-flight scan
    /// when a newer one is requested, so a slow scan of the folder the user just
    /// navigated away from cannot land on top of a newer result.
    @State private var rescanToken = 0

    private var targetFolder: URL? {
        folder ?? state.preferences.watchedFolders.first
    }

    private var selectedMoves: [PlannedMove] {
        preview.selectedMoves(excluding: excluded)
    }

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
        .task(id: rescanToken) { await rescan() }
        // The plan has to be re-read when this sheet is shown again, and
        // `.onAppear`/`.task` are not enough on their own. Measured on macOS
        // 26.6: dismissing the menu bar panel while this sheet is up hides both
        // and *keeps them alive* — the same view instance, its `@State` intact —
        // and reopening the panel restores the sheet without firing `.onAppear`
        // or `.task` a second time. A plan computed once would sit there frozen
        // while the watcher kept filing underneath it. `didBecomeKey` does fire
        // on that reopen, which makes it the trigger that actually works. It is
        // the same technique, for the same reason, as `ShelfView`'s row refresh.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in
            rescanToken += 1
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Organize Now").font(.headline)

            Text("Folders move whole — Ledge never looks inside them.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Nothing is overwritten. A name already in use gets a number.")
                .font(.caption)
                .foregroundStyle(.secondary)

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
        } else if preview.isEmpty {
            message(isScanning
                    ? "Looking through this folder…"
                    : "Nothing left to organize in this folder.")
        } else {
            List(preview.groups) { group in
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
            .frame(height: 260)
        }
    }

    private var footer: some View {
        HStack {
            if let batch = lastBatch {
                Button("Undo Last Batch") { undo(batch) }
                    .disabled(isMoving)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(action: startMove) { Text(moveButtonTitle) }
                .keyboardShortcut(.defaultAction)
                .disabled(isMoving || selectedMoves.isEmpty)
        }
        .padding(12)
    }

    /// A failed move would otherwise be invisible here: `AppState` records it in
    /// `lastError`, but the only thing that renders that is the shelf, and this
    /// sheet is sitting on top of the shelf. A batch that silently moved fewer
    /// files than the button promised is exactly the kind of lie this screen
    /// cannot afford.
    @ViewBuilder
    private var errorBanner: some View {
        if let error = state.lastError {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Button {
                    state.clearError()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help(String(localized: "Dismiss"))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
        }
    }

    private func message(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
    }

    private var moveButtonTitle: LocalizedStringKey {
        isMoving ? "Moving…" : "Move \(selectedMoves.count)"
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
    private func startMove() {
        guard let root = targetFolder else { return }
        let moves = selectedMoves
        isMoving = true
        Task {
            lastBatch = await state.apply(moves, root: root)
            isMoving = false
            rescanToken += 1
        }
    }

    private func undo(_ batch: UUID) {
        isMoving = true
        Task {
            await state.undoBatch(batch)
            lastBatch = nil
            isMoving = false
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
