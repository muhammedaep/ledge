import AppKit
import Combine
import SwiftUI
import LedgeCore

/// What a row needs from the filesystem, read in one sweep off the main actor.
private struct RowStatus: Sendable {
    let isPresent: Bool
}

/// The menu bar panel: where downloads are being filed, what was filed
/// recently, and the handful of actions that operate on the whole app.
struct ShelfView: View {
    @Environment(AppState.self) private var state
    /// Opens the Settings scene from a closure, for the unavailable-folder
    /// banner's action — `SettingsLink` is a view and cannot be called from one.
    @Environment(\.openSettings) private var openSettings
    @State private var showingOrganize = false
    /// Height the rows want, measured; the shelf clamps it to the user's.
    @State private var rowsHeight: CGFloat = 0
    /// Height at the moment a resize drag began, so the drag is relative.
    @State private var heightAtDragStart: Double?
    /// than off the pointer.
    /// Whether the destination list is open under the chip.
    @State private var isPickingDestination = false
    /// The height while a drag is in flight, before it is committed.
    ///
    /// Local on purpose. Writing each drag increment straight to `Preferences`
    /// put a `UserDefaults` write and an `@Observable` invalidation inside
    /// every mouse-move: the whole shelf rebuilt, the rows re-measured, and the
    /// height visibly juddered under the cursor. The drag now moves this, and
    /// only the release is persisted.
    @State private var liveHeight: Double?

    /// Liveness per record id, refreshed whenever the shelf appears.
    ///
    /// This has to be stored rather than computed in `body`. A `MoveRecord`
    /// outlives the file it describes, but "does that file still exist" has no
    /// observable dependency for SwiftUI to react to, and nothing re-renders
    /// the shelf when the popover opens — so a computed check is evaluated once
    /// and then frozen. A row would stay bright with undo enabled after its
    /// file was gone, or stay dimmed after it came back, until the next
    /// download happened to refresh the list.
    @State private var rowStatus: [UUID: RowStatus] = [:]

    /// Bumped by every `refreshRowStatus()`; a sweep that finishes after a later
    /// one started publishes nothing.
    ///
    /// The same guard `AppState.refreshFolderStatus` carries, for the same
    /// hazard, because the two are launched together from both closures below
    /// and race the same way. `rowStatus` is replaced wholesale, so an older
    /// sweep landing last publishes a dictionary built from a record list that
    /// no longer exists: a download filed while it was running has no entry, and
    /// its row sits with a stale liveness answer until some unrelated event
    /// refreshes the shelf. Nothing *does* the wrong thing —
    /// `ShelfRow.isStillThere()` re-reads at gesture time — but the shelf shows
    /// a stale answer, which is precisely what this sweep exists to prevent.
    @State private var rowStatusGeneration = 0

    /// This view's own panel, so the refresh below can tell it from Settings
    /// being brought forward. Same device, same reason, as `OrganizeSheet`'s.
    @State private var shelfWindow: NSWindow?

    var body: some View {
        // The permission screen replaces the *list*, never the footer. Settings
        // and Quit are the only two routes out of this window — Ledge is an
        // accessory app, so there is no app menu behind it — and a state that
        // hides them is a state the user cannot leave except through Activity
        // Monitor. That is worse than the problem the screen exists to explain,
        // and it was reachable by merely ejecting a drive.
        VStack(alignment: .leading, spacing: 0) {
            // Outside the branch for the same reason the footer is. A banner
            // that lives inside the thing being replaced is silent in exactly
            // the state it was written for: `lastError` set while the
            // permission screen is up used to render nothing at all.
            unavailableFolderBanner

            errorBanner

            if showsPermissionScreen {
                PermissionView()
            } else {
                shelf
            }

            Divider()

            footer

            undoShortcut
        }
        .frame(width: 360)
        // The boards specify a translucent fill and a 36pt blur, which is how
        // the web imitates macOS vibrancy. A material is the real thing: it
        // behaves correctly over any wallpaper and in both themes, which a
        // fixed rgba cannot. Spec §8.2.
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
            shape.fill(.regularMaterial)
            // Drawn over the material, not behind it: a second `.background`
            // would sit underneath and the material would hide it. Clear in
            // light, so this costs the light appearance nothing.
            shape.fill(Theme.Colour.panelGround)
        }
        .background(WindowReader { window in
            shelfWindow = window
            configure(window)
        })
        .sheet(isPresented: $showingOrganize) {
            OrganizeSheet()
                .environment(state)
        }
        // Fires when the shelf appears, and again whenever the record list
        // changes under it.
        .task(id: state.recentRecords.map(\.id)) {
            await refreshRowStatus()
            await state.refreshFolderStatus()
        }
        // A second, independent trigger, because the first depends on something
        // this session could not verify: whether SwiftUI re-runs `.task` each
        // time a `MenuBarExtra(style: .window)` popover is shown, or creates the
        // content once and keeps it alive. The popover's panel becomes key when
        // it opens, so this covers the case where the view survives and `.task`
        // does not re-run. Either trigger alone is enough; both are cheap.
        //
        // Folder access rides the same two signals, for the same reason: it
        // changes outside this process — in System Settings, or when a drive is
        // plugged back in — and the popover opening is exactly when a stale
        // answer would be seen.
        //
        // Filtered to this panel, the way `OrganizeSheet` already filters to
        // its own, because the notification is global: unfiltered, merely
        // opening Settings fired a full row sweep *and* an `O(entries)` access
        // check per watched folder. Both run off the main actor, so it was
        // never a freeze — just work nobody asked for, on the exact signal that
        // means the shelf is not being looked at.
        //
        // The Organize sheet counts as this panel deliberately. It is presented
        // from here and reads `state.isUsable(_:)` for the folder it has
        // selected, so its window becoming key is precisely when that answer
        // must not be stale. Its `sheetParent` is this panel, which is what
        // distinguishes it from Settings.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { note in
            // `shelfWindow` is bound first on purpose: both it and
            // `becameKey.sheetParent` are optional, and before this view has
            // been placed in a window `nil === nil` would match every plain
            // window in the app — the opposite of a filter.
            guard let shelfWindow,
                  let becameKey = note.object as? NSWindow,
                  becameKey === shelfWindow || becameKey.sheetParent === shelfWindow
            else { return }
            Task {
                await refreshRowStatus()
                await state.refreshFolderStatus()
            }
        }
    }

    /// Stops the panel closing itself on every single click.
    ///
    /// `MenuBarExtra(style: .window)` presents its content in an `NSPanel`.
    /// Ledge is an accessory app (`LSUIElement`), so it is never the active
    /// application while that panel is open — and an `NSPanel` hides itself the
    /// moment its app is not active. The click is delivered first, so the
    /// action happens; the shelf just vanishes underneath it. Anything needing
    /// two clicks — pick a destination, then undo a row — meant opening the
    /// shelf twice. Reported from the first real run.
    ///
    /// Deliberately *not* fixed by calling `NSApp.activate`. That would work,
    /// and it would also pull focus off whatever app is in front every time the
    /// shelf opens — in an app whose entire purpose is dragging a file into
    /// that other app.
    private func configure(_ window: NSWindow?) {
        guard let panel = window as? NSPanel else { return }
        panel.hidesOnDeactivate = false
        // A panel that takes key status "only if needed" hands it straight back
        // after a click on a control that does not need it, which is the same
        // dismissal by a second route.
        panel.becomesKeyOnlyIfNeeded = false
    }

    /// Whether the whole list is replaced by the explanation.
    ///
    /// Only when nothing is coming in from anywhere *and* permission is the
    /// reason. One blocked folder alongside a working one leaves filing running,
    /// so the list stays and the banner carries the news; every folder merely
    /// missing is not a permission problem and gets the banner too.
    private var showsPermissionScreen: Bool {
        !state.hasUsableFolder && !state.unreadableFolders.isEmpty
    }

    /// Three rows, until the user says otherwise.
    ///
    /// Derived from what the rows actually measured rather than a constant:
    /// a row's height follows its type size and padding, so a hard-coded
    /// default would be wrong the first time either changed.
    private var defaultListHeight: Double {
        let count = max(state.recentRecords.count, 1)
        return Double(rowsHeight) / Double(count) * 3
    }

    /// How tall the list is allowed to be right now.
    private var listHeight: Double {
        let wanted = liveHeight ?? state.preferences.shelfHeight ?? defaultListHeight
        return min(max(wanted, Self.minListHeight), Self.maxListHeight)
    }

    private static let minListHeight: Double = 52
    private static let maxListHeight: Double = 520

    /// The drag handle under the list.
    ///
    /// A menu bar panel cannot be resized from its window edges — the panel
    /// `MenuBarExtra(style: .window)` puts the shelf in has no resize control
    /// and SwiftUI sizes it from the content — so the shelf carries its own.
    private var resizeGrip: some View {
        Capsule()
            .fill(Theme.Colour.chipBorder)
            .frame(width: 28, height: 3)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .gesture(
                // `.global`, not the default local space. The grip is part of
                // what it resizes: as the list grows the handle moves down with
                // it, so a translation measured locally is taken from an origin
                // that has itself shifted since the drag began. That feeds back
                // and the height oscillates under the cursor. Screen
                // coordinates do not move, so the drag stays stable.
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = heightAtDragStart ?? listHeight
                        heightAtDragStart = start
                        liveHeight = min(
                            max(start + value.translation.height, Self.minListHeight),
                            Self.maxListHeight)
                    }
                    .onEnded { _ in
                        state.preferences.shelfHeight = listHeight
                        heightAtDragStart = nil
                        liveHeight = nil
                    }
            )
            .help("Drag to resize the shelf")
            // push/pop, not set/set: `set()` on both edges of the hover leaves
            // AppKit's cursor stack unbalanced and the cursor flickers between
            // the two shapes while the pointer sits still.
            .onHover { inside in
                if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
            }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader

            Text("RECENT DOWNLOADS")
                .sectionLabel()
                .padding(.horizontal, Theme.Space.panel)
                .padding(.top, Theme.Space.section)
                .padding(.bottom, 5)

            if state.recentRecords.isEmpty {
                // Centred, with the menu bar's own icon above it, and the
                // headline at plain weight — all three from the design, which
                // this had left-aligned, iconless and semibold.
                VStack(spacing: 2) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 22, weight: .light))
                        .opacity(0.3)
                        .padding(.bottom, 6)
                    Text("Nothing filed yet")
                        .font(.system(size: 13))
                    // The only line in the app that explains the product.
                    Text("New downloads appear here — drag any row to use the file.")
                        .rowMeta()
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 26)
                .padding(.horizontal, 20)
                .padding(.bottom, 30)
            } else {
                ScrollView {
                    VStack(spacing: Theme.Space.rowGap) {
                        ForEach(state.recentRecords) { record in
                            // Until the first sweep lands, a row shows as
                            // present: the display is briefly optimistic, while
                            // the row's own gesture-time check keeps what it
                            // *does* correct either way.
                            ShelfRow(
                                record: record,
                                isPresent: rowStatus[record.id]?.isPresent ?? true,
                                projectName: projectName(for: record)
                            ) {
                                // `undo` is async, so the row's synchronous
                                // button action hands it to a task.
                                Task { await state.undo(record) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                    .background(
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: RowsHeight.self, value: proxy.size.height)
                        }
                    )
                }
                // Measured, then clamped — neither half is optional.
                //
                // `MenuBarExtra(style: .window)` sizes its panel from the
                // content's ideal height, and a `ScrollView` has no ideal
                // height of its own: it takes what it is proposed, and here it
                // is proposed zero. Shipped, that resolved to {360, 0} and no
                // row rendered at all while the shelf still held ten records.
                //
                // `fixedSize` looks like the fix and is not: it makes the view
                // ignore *every* proposal, including the `maxHeight` cap, so a
                // ten-row shelf drew 475pt over its own header and footer.
                // Both states were measured from the running panel's view tree.
                //
                // So the content reports its own height and this frame clamps
                // it. `VStack`, not `LazyVStack`: a lazy stack inside a
                // zero-height scroll view renders nothing and would report zero
                // forever, which is the deadlock this measurement must avoid.
                // Whole points, and no implicit animation: this frame drives an
                // NSPanel resize on every drag event, and a fractional or
                // animated height makes the window chase the cursor.
                .frame(height: (min(rowsHeight, listHeight)).rounded())
                .animation(nil, value: listHeight)
                .onPreferenceChange(RowsHeight.self) { rowsHeight = $0 }

                resizeGrip
            }
        }
    }

    /// The project a record was filed under, or nil.
    ///
    /// Matched by containment rather than stored on the record, because
    /// `MoveRecord` deliberately records where a file was *found* — that is
    /// what undo needs — and a project changes only where it went.
    ///
    /// The deepest matching folder wins, not the first: `Project.choosing`
    /// dedupes identical folders but nothing stops one project's folder from
    /// sitting inside another's, and the first match in `state.projects`
    /// would then name the outer project for a file that was actually filed
    /// into the inner one — wrong in the one line whose entire job is saying
    /// where a file went.
    private func projectName(for record: MoveRecord) -> String? {
        state.projects
            .filter { record.to.path.hasPrefix($0.folder.path + "/") }
            .max { $0.folder.path.count < $1.folder.path.count }?
            .name
    }

    /// Organize, Settings and Quit. Rendered outside `shelf` so that no state —
    /// including one where Ledge cannot read a thing — can take them away.
    private var footer: some View {
        HStack(spacing: 0) {
            Button("Organize Now…") { showingOrganize = true }
                .buttonStyle(.plain)
                .rowName()
                .foregroundStyle(Theme.Colour.accent)
                // Only when there is nowhere left to organize *from*.
                .disabled(!state.hasUsableFolder)

            Spacer()

            // Not `SettingsLink`, which opens the window without raising it.
            // Ledge is an accessory app (LSUIElement) and is never frontmost
            // while the shelf is open, so Settings appeared *behind* whatever
            // the user was working in — reported from a real run. The banner's
            // button below and `chooseProject()` already pair `activate` with
            // the action for exactly this reason; this is the third case, and
            // it was the one anybody would actually click.
            Button {
                NSApplication.shared.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: Theme.Size.button)
            }
            .buttonStyle(HoverGlyphButtonStyle())
            .foregroundStyle(Theme.Colour.textSecondary)
            .help(String(localized: "Settings"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 28, height: Theme.Size.button)
            }
            .buttonStyle(HoverGlyphButtonStyle())
            .foregroundStyle(Theme.Colour.textSecondary)
            .help(String(localized: "Quit Ledge"))
        }
        .padding(.leading, Theme.Space.panel)
        .padding(.trailing, 6)
        .frame(height: Theme.Size.footer)
    }

    /// ⌘Z, which spec §7.5 promised and nothing ever built.
    ///
    /// A zero-sized `Button` rather than an `onKeyPress` or a menu command,
    /// because that is what scopes it. SwiftUI registers a `keyboardShortcut`
    /// with the window whose hierarchy holds the button, so this one is live
    /// exactly while the shelf panel is key. Settings is a separate window: ⌘Z
    /// there stays text undo in a rules field, which is what the user means by
    /// it while typing a category name.
    ///
    /// All of that was measured on a `MenuBarExtra(style: .window)` panel rather
    /// than assumed, since that panel is already known to treat `.onAppear` and
    /// `.task` unlike a normal window. Driving the status item to open the panel
    /// and handing it a real ⌘Z event: the panel is key, `performKeyEquivalent`
    /// returns true, and the action runs. Disabled, it returns false and the
    /// action does not run — which is why `canUndo` drives `.disabled` and not
    /// an early return: an empty shelf leaves the keystroke unconsumed instead
    /// of raising an error about nothing.
    ///
    /// The frame is zeroed rather than only `.hidden()`, which still takes
    /// layout space and would open a button-sized gap under the footer. This
    /// exact chain was the one verified.
    private var undoShortcut: some View {
        Button("Undo") {
            Task { await state.undoMostRecent() }
        }
        .keyboardShortcut("z", modifiers: .command)
        .disabled(!state.canUndo)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    /// Watched folders Ledge cannot file from, and why, for every case the
    /// permission screen is not already up for.
    ///
    /// A folder that is simply *gone* — an ejected drive, a deleted directory —
    /// is never a permission problem: no consent dialog can grant a folder that
    /// is not there. A *blocked* folder is, but if another folder still works
    /// then filing is still running and only a banner is owed; the full screen
    /// would hide a live list to explain a partial failure.
    @ViewBuilder
    private var unavailableFolderBanner: some View {
        // Whatever the permission screen is already saying does not need saying
        // twice.
        let blocked = showsPermissionScreen ? [] : state.unreadableFolders
        let unavailable = state.missingFolders + blocked
        if !unavailable.isEmpty {
            // The same amber pill as `errorBanner`, not the `ErrorBanner` type
            // itself: that struct's `message` is a single string, and this
            // banner has two registers to keep apart — the sentence, and the
            // folder names, which stay `.secondary` rather than sharing the
            // warning colour. The action branches exactly the way the icon
            // above it already does: a folder that is merely gone is fixed by
            // re-picking it in Settings, but a folder TCC has denied is fixed
            // only in Privacy & Security — Settings has a status icon, Remove
            // and Add Folder…, and none of the three re-grants a folder that
            // is already watched. Re-adding the same folder through Add
            // Folder… is a no-op (`FolderIdentity.adding` dedupes it before
            // `AppState.addWatchedFolder` ever calls `startWatching()`), so
            // "Choose Folder Again…" would open a pane with nothing in it
            // that fixes a blocked folder — exactly the state this banner
            // exists to explain.
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: blocked.isEmpty
                      ? "externaldrive.trianglebadge.exclamationmark"
                      : "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(unavailable.count == 1
                         ? String(localized: "Ledge can't file from a watched folder right now.")
                         : String(localized: "Ledge can't file from \(unavailable.count) watched folders right now."))
                        .rowMeta(AnyShapeStyle(Theme.Colour.amber))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(unavailable.map(\.lastPathComponent).joined(separator: ", "))
                        .rowMeta()
                        .lineLimit(1)
                        .truncationMode(.head)
                    Button(blocked.isEmpty
                           ? String(localized: "Choose Folder Again…")
                           : String(localized: "Open Privacy Settings")) {
                        if blocked.isEmpty {
                            // `openSettings()` alone was not verified to raise
                            // the window over whatever the user is in front of
                            // — Ledge is an accessory app (LSUIElement) and
                            // never frontmost while the shelf is open, the
                            // same reason `chooseProject()` below activates
                            // before its own panel. Keeping the pairing rather
                            // than assuming the environment action already
                            // covers it.
                            NSApplication.shared.activate(ignoringOtherApps: true)
                            openSettings()
                        } else {
                            // The one place a denied TCC grant can be
                            // reversed — Settings' General pane has no control
                            // that does this.
                            PrivacySettings.open()
                        }
                    }
                    .buttonStyle(.plain)
                    .actionLink()
                    .foregroundStyle(Theme.Colour.amber)
                    .underline()
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colour.amberFill)
            }
            .padding(.horizontal, Theme.Space.panel)
            .padding(.top, 8)
        }
    }

    /// Re-reads liveness for every record currently on the shelf.
    ///
    /// Off the main actor deliberately. The liveness check is a filesystem
    /// read, run once per record, and a menu bar icon that does nothing when
    /// clicked is the worst failure this view has.
    ///
    /// The read that genuinely blocks is one against an unresponsive network
    /// mount, which stalls until the mount times out. Not a *local* volume being
    /// detached, which this comment used to claim and which measures at 0.0023 s
    /// — precautionary there, and cheap enough to keep on that basis, but the
    /// reason had to stop being one anyone could disprove in half a minute.
    private func refreshRowStatus() async {
        rowStatusGeneration += 1
        let generation = rowStatusGeneration
        let records = state.recentRecords

        let swept = await Task.detached(priority: .userInitiated) {
            var status: [UUID: RowStatus] = [:]
            for record in records {
                status[record.id] = RowStatus(
                    // `FileEntry.exists`, not `fileExists`: undo and the mover
                    // both count a dangling symlink as a file that is there, so
                    // a row that dimmed itself and disabled its own undo button
                    // was describing a file the rest of the app can still move.
                    isPresent: FileEntry.exists(atPath: record.to.path)
                )
            }
            return status
        }.value

        guard generation == rowStatusGeneration else { return }
        rowStatus = swept
    }

    /// `AppState` records six different failures and, until now, showed none
    /// of them. For an app whose whole job is moving the user's files, a failed
    /// undo that reports nothing is worse than one that never happened.
    private var errorBanner: some View {
        ErrorBanner(message: state.lastError, horizontalPadding: 12, topPadding: 8,
                    action: state.lastErrorOffersPrivacySettings
                        ? (String(localized: "Open Privacy Settings"), { PrivacySettings.open() })
                        : nil) {
            state.clearError()
        }
    }

    /// Names where downloads are going right now, and lets the user change it.
    /// Without this, project mode is invisible: nothing else in the shelf says
    /// which folder the next download will land in.
    private var destinationHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Label and End on one row, pushed apart — the design's layout.
            // They were stacked at opposite ends of the header with the chip
            // and a sentence between them, so the control that leaves project
            // mode sat as far as it could get from the label announcing it.
            HStack(alignment: .firstTextBaseline) {
                Text(state.activeProject == nil
                     ? String(localized: "FILING INTO")
                     : String(localized: "PROJECT MODE"))
                    .sectionLabel()

                if let project = state.activeProject {
                    Spacer(minLength: 8)
                    Button("End") { state.setActiveProject(nil) }
                        .buttonStyle(.plain)
                        .actionLink()
                        .foregroundStyle(Theme.Colour.accent)
                        .accessibilityLabel(Text("End project \(project.name)"))
                }
            }

            ChipButton(title: state.activeProject?.name ?? defaultDestinationName) {
                isPickingDestination.toggle()
            }
            .accessibilityLabel(Text("Filing into"))

            // The list opens *inside* the panel, not as an `NSMenu`.
            //
            // Measured, after a menu was tried and shipped: a menu takes key
            // from the window it opens over, and `MenuBarExtra(style: .window)`
            // closes its panel the moment that panel is no longer key. The log
            // read `resignKey visible=1 appActive=1` and the panel was gone
            // before the next event. So every attempt to change destination
            // shut the shelf and the user had to reopen it from the menu bar
            // and start again. Nothing configurable on the panel prevents it —
            // `hidesOnDeactivate` covers deactivation, not loss of key.
            //
            // Staying in one window means key never moves, so the shelf cannot
            // be dismissed by its own control.
            if isPickingDestination {
                destinationList
            }

            if state.activeProject != nil {
                Text("All new downloads go here until you end the project.")
                    .rowMeta()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, Theme.Space.panel)
        // 10 above and 12 below in project mode, which is the design's; these
        // were the other way round.
        .padding(.top, state.activeProject == nil ? Theme.Space.panel : 10)
        .padding(.bottom, state.activeProject == nil ? 0 : Theme.Space.panel)
        .background(state.activeProject == nil ? Color.clear : Theme.Colour.accent.opacity(0.08))
        // The tinted header ends in a rule of its own, so project mode reads
        // as a band across the top rather than a colour that fades out.
        .overlay(alignment: .bottom) {
            if state.activeProject != nil {
                Rectangle()
                    .fill(Theme.Colour.accent.opacity(0.15))
                    .frame(height: 1)
            }
        }
    }

    /// What to call the no-project destination.
    ///
    /// Naming `watchedFolders.first` was wrong as soon as there was a second
    /// watched folder: `AppState.handle` files each download into the folder it
    /// was *found* in, so the header would confidently name one folder while
    /// everything found in the others went somewhere else — the single thing
    /// this header exists to prevent.
    private var defaultDestinationName: String {
        let folders = state.preferences.watchedFolders
        switch folders.count {
        case 0: return String(localized: "No Watched Folders")
        case 1: return folders[0].lastPathComponent
        default: return String(localized: "Each Download's Own Folder")
        }
    }

    /// The destinations, drawn in the panel under the chip.
    private var destinationList: some View {
        VStack(spacing: 1) {
            destinationRow(defaultDestinationName,
                           isActive: state.activeProject == nil) {
                state.setActiveProject(nil)
            }
            ForEach(state.projects) { project in
                // Removing goes through `updateProjects`, which drops the
                // active destination back to the watched folder if this was
                // it — the same path General takes. The list stays open: the
                // user is editing it, not choosing from it.
                destinationRow(project.name,
                               isActive: state.activeProject?.id == project.id,
                               remove: {
                                   state.updateProjects(state.projects.filter { $0.id != project.id })
                               }) {
                    state.setActiveProject(project)
                }
            }
            Divider().padding(.vertical, 3)
            destinationRow(String(localized: "Choose Project…"), isActive: false) {
                chooseProject()
            }
        }
        .padding(.top, 5)
    }

    /// `remove`, when given, puts a minus at the row's trailing end. Projects
    /// get one; the watched folder and `Choose Project…` do not.
    private func destinationRow(_ title: String,
                                isActive: Bool,
                                remove: (() -> Void)? = nil,
                                select: @escaping () -> Void) -> some View {
        Button {
            select()
            isPickingDestination = false
        } label: {
            HStack(spacing: 7) {
                // The checkmark keeps its width when absent, so the names stay
                // on one left edge instead of shifting as the choice changes.
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .bold))
                    .opacity(isActive ? 1 : 0)
                    .frame(width: 10)
                Text(title)
                    .rowName()
                    .lineLimit(1)
                    .truncationMode(.middle)
                // Room for the minus, so a long name truncates before it
                // rather than running underneath it.
                Spacer(minLength: remove == nil ? 0 : 24)
            }
            .padding(.horizontal, 9)
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(HoverRowButtonStyle())
        // Beside the row's button rather than inside its label: a button
        // nested in another button's label shares its press, and a click on
        // the minus would also select the project it was removing.
        .overlay(alignment: .trailing) {
            if let remove {
                Button(role: .destructive, action: remove) {
                    Image(systemName: "minus.circle")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colour.textTertiary)
                        .frame(width: 24, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, 3)
                .accessibilityLabel(Text("Remove project"))
                .help(Text("Remove project"))
            }
        }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // Ledge is an accessory app (LSUIElement), so it is never frontmost
        // when the shelf is open. Without this the panel opens behind whatever
        // the user was working in.
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Whether a chosen folder is already a project is a rule, not a
        // rendering concern, so it lives in LedgeCore with tests. Appending
        // unconditionally here used to add a second, indistinguishable entry
        // every time the user picked a folder they had picked before —
        // `Project(folder:)` mints a fresh id on each call.
        let choice = Project.choosing(url, in: state.projects)
        // A project the write refused is not one to switch to. `activeProject`
        // looks the id up in `projects`, which no longer moves ahead of the
        // file, so activating it would leave the preference pointing at a
        // project this list does not contain and the header naming the default
        // destination with no explanation.
        guard choice.wasAlreadyKnown || state.updateProjects(choice.projects) else { return }
        state.setActiveProject(choice.project)
    }
}

/// The rows' natural height, reported up so the scroll view can be given a
/// definite one. See the note at the `frame` that consumes it.
private struct RowsHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
