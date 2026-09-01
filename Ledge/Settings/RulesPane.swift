import LedgeCore
import SwiftUI

/// `objc/runtime.h` exports `typedef struct objc_category *Category`, and
/// SwiftUI drags the ObjC runtime headers in behind it, so the bare name is
/// ambiguous for type lookup in this target. Saying once which one this file
/// means beats qualifying it at every mention.
private typealias Category = LedgeCore.Category

/// Settings › Rules: the categories, what each one claims, the order they are
/// matched in, and how each one subdivides its folder.
///
/// Two properties shape the whole pane.
///
/// *Order is meaning.* Categories are matched top to bottom and the first one
/// claiming a file's extension wins, so moving a row is a real edit — the same
/// edit as retyping both rows' extension lists. It therefore gets explicit
/// buttons rather than only a drag: a drag that is hard to land is a change the
/// user cannot make.
///
/// *Saving is a commit.* Everything here edits a draft. Nothing files against a
/// half-typed extension list, and nothing is written until Save — which is also
/// why the draft survives a tab switch instead of being silently reloaded from
/// disk under the user's unsaved work.
struct RulesPane: View {
    @Environment(AppState.self) private var state

    @State private var draft = RuleSet.defaults
    @State private var hasLoadedDraft = false
    @State private var confirmingReset = false

    /// Bumped whenever the draft is committed or replaced wholesale, to tell
    /// every row's extensions field to stop showing what was typed and show what
    /// was stored. A counter rather than a flag: two saves in a row have to be
    /// two separate events.
    @State private var tidyToken = 0

    /// Set when a Save was refused or failed to write, cleared as soon as the
    /// draft changes — a stale "couldn't save" beside a draft the user has since
    /// fixed would be its own small lie.
    @State private var saveFailed = false

    private var isDirty: Bool { draft != state.rules }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
            Divider()
            footer
        }
        .onAppear {
            // Once. `onAppear` fires again every time the user comes back to
            // this tab, and re-seeding there would throw away unsaved edits
            // with no warning and no way back.
            guard !hasLoadedDraft else { return }
            draft = state.rules
            hasLoadedDraft = true
        }
        // The complaint belongs to the draft that earned it.
        .onChange(of: draft) { saveFailed = false }
        .confirmationDialog(
            "Replace your categories with the defaults?",
            isPresented: $confirmingReset
        ) {
            Button("Reset to Defaults", role: .destructive) { replaceDraft(with: .defaults) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every category you have added or changed is discarded. Nothing is written until you save.")
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Categories are matched top to bottom. The first one claiming a file's extension wins.")
            Text("Renaming a category doesn't move files that were already filed under the old name.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    // MARK: - The categories

    private var list: some View {
        // Computed once per pass rather than per row: `problems` walks every
        // extension in the rule set, and every row would otherwise ask for the
        // whole list to find its own.
        let problems = Dictionary(grouping: draft.problems, by: \.category)

        return List {
            ForEach($draft.categories) { $category in
                CategoryRow(
                    category: $category,
                    messages: messages(from: problems[category.id] ?? []),
                    position: position(of: category.id),
                    tidyToken: tidyToken,
                    move: { offset in move(category.id, by: offset) },
                    remove: { remove(category.id) }
                )
                .padding(.vertical, 4)
            }
            // Dragging works too, where the pointer cooperates; the row's
            // buttons are the path that always does.
            .onMove { draft.categories.move(fromOffsets: $0, toOffset: $1) }

            fallbackRow(problems: problems[nil] ?? [])
        }
    }

    /// The fallback is part of the rule set, not a category: it claims nothing,
    /// it is always last, and it cannot be removed — every unmatched file has
    /// to land somewhere.
    private func fallbackRow(problems: [RuleSet.Problem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Everything else")
                    .font(.body.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Other", text: $draft.fallbackName)
                    .textFieldStyle(.roundedBorder)
            }
            MessageList(messages: messages(from: problems))
        }
        .padding(.vertical, 4)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            // Appended, not inserted: last place is the only position that
            // cannot take an extension away from a rule the user already has.
            Button("Add Category") {
                draft.categories.append(Category(name: String(localized: "New Category"), extensions: []))
            }
            Button("Reset to Defaults") { confirmingReset = true }

            Spacer()

            // A failed save is reported here, next to the button that failed.
            // `AppState.lastError` alone would not do: it is rendered by the
            // shelf and the Organize sheet, so a refusal earned by clicking
            // Save in Settings would appear in the menu bar popover instead —
            // somewhere the user is not looking.
            if saveFailed {
                Text("Couldn't save. Nothing was changed.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if !draft.canBeSaved {
                Text("Fix the highlighted name to save.")
                    .font(.caption)
                    .foregroundStyle(.red)
            } else if isDirty {
                Text("Unsaved changes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button("Discard Changes") {
                replaceDraft(with: state.rules)
                saveFailed = false
            }
            .disabled(!isDirty)
            Button("Save") {
                saveFailed = !state.updateRules(draft)
                // A save is what makes the stored spelling the truth, so it is
                // what the fields have to catch up to. A refused one changed
                // nothing, so there is nothing for them to catch up to.
                if !saveFailed { tidyToken += 1 }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!isDirty || !draft.canBeSaved)
        }
        .padding(10)
    }

    // MARK: - Editing

    /// Where a category sits, so a row can tell whether it has anywhere to move.
    private func position(of id: Category.ID) -> RowPosition {
        guard let index = draft.categories.firstIndex(where: { $0.id == id }) else {
            return RowPosition(canMoveUp: false, canMoveDown: false)
        }
        return RowPosition(
            canMoveUp: index > 0,
            canMoveDown: index < draft.categories.count - 1
        )
    }

    /// Swaps the whole draft out — a reset or a discard — and tells the rows,
    /// because a row that keeps its identity across the swap keeps its typed
    /// text too. `RuleSet.defaults` is a `static let`, so resetting a
    /// never-saved rule set hands back categories with the very same ids.
    private func replaceDraft(with newDraft: RuleSet) {
        draft = newDraft
        tidyToken += 1
    }

    private func move(_ id: Category.ID, by offset: Int) {
        guard let index = draft.categories.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard draft.categories.indices.contains(target) else { return }
        draft.categories.swapAt(index, target)
    }

    private func remove(_ id: Category.ID) {
        draft.categories.removeAll { $0.id == id }
    }

    // MARK: - Saying what is wrong

    /// `RuleSet.problems` decides what is wrong; this decides how to say it.
    /// Grouped by row, and shadowed extensions grouped again by the category
    /// that takes them, so one badly-placed rule reads as one sentence rather
    /// than as a line per extension.
    private func messages(from problems: [RuleSet.Problem]) -> [RuleMessage] {
        var messages: [RuleMessage] = []
        var shadowed: [(claimedBy: String, extensions: [String])] = []

        for problem in problems {
            switch problem {
            // The fault comes from LedgeCore rather than being re-derived here.
            // Asking "is this name blank" a second time, with this file's own
            // idea of whitespace, is how a name of "\n" ends up being told it
            // contains a slash.
            case .unusableName(_, _, .blank):
                messages.append(RuleMessage(
                    text: String(localized: "This needs a folder name before it can be saved."),
                    isBlocking: true))
            case .unusableName(_, _, .notAFolderName):
                messages.append(RuleMessage(
                    text: String(localized: "A folder name can't contain “/” or “:”, or be only dots."),
                    isBlocking: true))

            // Two shapes, because only one of them is true on every disk. What
            // both have to say is the part that is easy to miss: each rule keeps
            // its own subfolder setting, so one folder ends up holding one
            // rule's PNG/ next to the other's 2026-09/.
            case let .duplicateName(_, name, true):
                messages.append(RuleMessage(
                    text: String(localized: """
                        Another rule is also called “\(name)”. They share one folder, \
                        each still applying its own subfolder setting inside it.
                        """),
                    isBlocking: false))
            case let .duplicateName(_, name, false):
                messages.append(RuleMessage(
                    text: String(localized: """
                        Another rule's name differs from “\(name)” only in capitalisation or \
                        accent spelling. On a case-insensitive disk — the macOS default — that \
                        is one folder, holding both rules' subfolders.
                        """),
                    isBlocking: false))
            case .hiddenName:
                messages.append(RuleMessage(
                    text: String(localized: "A name starting with a dot is hidden in the Finder."),
                    isBlocking: false))
            case .noConditions:
                messages.append(RuleMessage(
                    text: String(localized: "No extensions and no patterns, so nothing is ever filed here."),
                    isBlocking: false))
            case let .shadowedExtension(_, ext, claimedBy):
                if let existing = shadowed.firstIndex(where: { $0.claimedBy == claimedBy }) {
                    shadowed[existing].extensions.append(ext)
                } else {
                    shadowed.append((claimedBy: claimedBy, extensions: [ext]))
                }
            }
        }

        for group in shadowed {
            let list = group.extensions.map { ".\($0)" }.formatted(.list(type: .and))
            messages.append(RuleMessage(
                text: String(localized: "\(group.claimedBy) is higher up and already takes \(list), so they never reach here."),
                isBlocking: false))
        }
        return messages
    }
}

// MARK: - One category

/// Whether this row has anywhere to move. Computed by the pane, which is the
/// only thing that knows the order.
private struct RowPosition: Equatable {
    let canMoveUp: Bool
    let canMoveDown: Bool
}

private struct RuleMessage: Hashable {
    let text: String
    let isBlocking: Bool
}

private struct MessageList: View {
    let messages: [RuleMessage]

    var body: some View {
        ForEach(messages, id: \.self) { message in
            Text(message.text)
                .font(.caption)
                .foregroundStyle(message.isBlocking ? Color.red : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct CategoryRow: View {
    @Binding var category: Category
    let messages: [RuleMessage]
    let position: RowPosition
    /// Bumped by the pane whenever the draft is committed or replaced, which is
    /// the moment the field has to stop showing a draft spelling.
    let tidyToken: Int
    let move: (Int) -> Void
    let remove: () -> Void

    /// The extensions field as typed, kept separate from the parsed list.
    ///
    /// Binding the field straight to `category.extensions` through a formatting
    /// getter makes it unusable: every keystroke re-renders the field from the
    /// parsed list, which eats the space you just typed before you can type the
    /// next extension, and eats a comma or a dot outright. The text is the
    /// user's; the list is derived from it.
    @State private var typedExtensions: String

    /// Whether the field has the keyboard. Losing it is the ordinary end of an
    /// edit — far more common than pressing Return — and so the ordinary moment
    /// to show what was stored.
    @FocusState private var isEditingExtensions: Bool

    init(
        category: Binding<Category>,
        messages: [RuleMessage],
        position: RowPosition,
        tidyToken: Int,
        move: @escaping (Int) -> Void,
        remove: @escaping () -> Void
    ) {
        _category = category
        _typedExtensions = State(initialValue: category.wrappedValue.extensionsField)
        self.messages = messages
        self.position = position
        self.tidyToken = tidyToken
        self.move = move
        self.remove = remove
    }

    /// What parsing changed that the user could not have predicted, said out
    /// loud instead of only being applied.
    ///
    /// Shown while the field still holds the original spelling, and gone by
    /// itself once `tidy()` has replaced it — so the sequence a user sees is
    /// "here is why", then "here is the result", rather than a silent swap.
    private var rewriteNotes: [RuleMessage] {
        let rewrites = Category.extensionRewrites(in: typedExtensions)
        guard !rewrites.isEmpty else { return [] }

        var notes: [RuleMessage] = []
        let kept = rewrites.compactMap { rewrite in
            rewrite.stored.map { "“\(rewrite.typed)” → “\($0)”" }
        }
        let dropped = rewrites.filter { $0.stored == nil }.map { "“\($0.typed)”" }

        if !kept.isEmpty {
            let list = kept.formatted(.list(type: .and))
            // "the last dot-separated piece", not "the part after the last
            // dot". The second is false whenever the token ends in a dot —
            // `a.b.` keeps `b`, while the part after its last dot is nothing —
            // and this sentence is the only thing the user is asked to trust
            // about what got stored. `everyReportedRewriteReallyKeptTheLastDotSeparatedPiece`
            // sweeps it.
            notes.append(RuleMessage(
                text: String(localized: """
                    Stored as \(list) — an extension is the last dot-separated piece of a name.
                    """),
                isBlocking: false))
        }
        if !dropped.isEmpty {
            let list = dropped.formatted(.list(type: .and))
            notes.append(RuleMessage(
                text: String(localized: """
                    Not stored: \(list) — a file extension can't contain “/” or “:”.
                    """),
                isBlocking: false))
        }
        return notes
    }

    /// Replaces the typed text with what is actually stored.
    ///
    /// Called when the edit ends, not while it runs: mid-typing this would eat
    /// the space or comma being typed.
    private func tidy() {
        let stored = category.extensionsField
        if typedExtensions != stored { typedExtensions = stored }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $category.name)
                    .textFieldStyle(.plain)
                    .font(.body.weight(.medium))

                TextField("Extensions", text: $typedExtensions)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption.monospaced())
                    .focused($isEditingExtensions)
                    .onSubmit(tidy)

                MessageList(messages: rewriteNotes)

                HStack(spacing: 6) {
                    Text("Subfolders")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("Subfolders", selection: $category.subdivision) {
                        Text("None").tag(Subdivision.none)
                        Text("By extension").tag(Subdivision.byExtension)
                        Text("By month").tag(Subdivision.byMonth)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                MessageList(messages: messages)
            }

            VStack(spacing: 2) {
                Button { move(-1) } label: { Image(systemName: "chevron.up") }
                    .disabled(!position.canMoveUp)
                    .help("Move up — earlier rules win ties")
                Button { move(1) } label: { Image(systemName: "chevron.down") }
                    .disabled(!position.canMoveDown)
                    .help("Move down — later rules only see what's left")
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                }
                .help("Remove this category")
            }
            .buttonStyle(.borderless)
        }
        // The draft is kept current on every keystroke, so clicking Save
        // without leaving the field still saves what is on screen.
        .onChange(of: typedExtensions) { _, text in
            let parsed = Category.parseExtensions(text)
            if parsed != category.extensions { category.extensions = parsed }
        }
        // The field follows the list when something other than typing changes
        // it — Reset to Defaults and Discard Changes both do, and the row
        // survives them when the category keeps its identity.
        //
        // This guard alone is not enough to keep the field honest, which is the
        // bug it used to hide: `.tar.gz` parses to `gz`, so the list and the
        // parse of the text agree, and nothing here fires while the field goes
        // on displaying `.tar.gz`. The two triggers below are what close it.
        .onChange(of: category.extensions) { _, list in
            if list != Category.parseExtensions(typedExtensions) {
                typedExtensions = list.joined(separator: " ")
            }
        }
        // Leaving the field ends the edit, so the field stops showing a
        // spelling that is not what got stored.
        .onChange(of: isEditingExtensions) { _, editing in
            if !editing { tidy() }
        }
        // …and so does a save, a reset or a discard. Clicking a button on
        // macOS does not necessarily take first responder away from a text
        // field, so focus alone would leave `.tar.gz` on screen after the very
        // save that stored `gz`.
        .onChange(of: tidyToken) { _, _ in tidy() }
    }
}
