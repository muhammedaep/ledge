import AppKit
import Combine
import SwiftUI
import LedgeCore

/// What a row needs from the filesystem, read in one sweep off the main actor.
///
/// `@unchecked Sendable` for the `NSImage`: it is built on the sweep's own
/// thread, never mutated afterwards, and only read on the main actor once the
/// sweep hands it over — so it is never touched from two places at once.
private struct RowStatus: @unchecked Sendable {
    let isPresent: Bool
    let icon: NSImage
}

/// The menu bar panel: where downloads are being filed, what was filed
/// recently, and the handful of actions that operate on the whole app.
struct ShelfView: View {
    @Environment(AppState.self) private var state
    @State private var showingOrganize = false

    /// Liveness and icon per record id, refreshed whenever the shelf appears.
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
    /// its row sits with a generic icon until some unrelated event refreshes the
    /// shelf. Nothing *does* the wrong thing — `ShelfRow.isStillThere()` re-reads
    /// at gesture time — but the shelf shows a stale answer, which is precisely
    /// what this sweep exists to prevent.
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

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader

            Text("RECENT DOWNLOADS")
                .sectionLabel()
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider()

            if state.recentRecords.isEmpty {
                Text("Nothing filed yet.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 28)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(state.recentRecords) { record in
                            // Until the first sweep lands, a row shows as
                            // present: the display is briefly optimistic, while
                            // the row's own gesture-time check keeps what it
                            // *does* correct either way.
                            ShelfRow(
                                record: record,
                                isPresent: rowStatus[record.id]?.isPresent ?? true,
                                icon: rowStatus[record.id]?.icon
                            ) {
                                // `undo` is async, so the row's synchronous
                                // button action hands it to a task.
                                Task { await state.undo(record) }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                .frame(maxHeight: 340)
            }
        }
    }

    /// Organize, Settings and Quit. Rendered outside `shelf` so that no state —
    /// including one where Ledge cannot read a thing — can take them away.
    private var footer: some View {
        HStack {
            Button("Organize Now…") { showingOrganize = true }
                // Only when there is nowhere left to organize *from*. This used
                // to ask the all-or-nothing `hasFolderAccess`, false the moment
                // any single watched folder was blocked — so one locked folder
                // disabled Organize Now for the readable one beside it, the same
                // mistake the shelf itself was moved off and this control was
                // left behind on. Which folder is being organized is the sheet's
                // own question, and it is the sheet that answers it: it has the
                // picker.
                .disabled(!state.hasUsableFolder)
            Spacer()
            SettingsLink { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .help(String(localized: "Settings"))
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Quit Ledge"))
        }
        .padding(10)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: blocked.isEmpty
                      ? "externaldrive.trianglebadge.exclamationmark"
                      : "lock.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(unavailable.count == 1
                         ? String(localized: "Ledge can't file from a watched folder right now.")
                         : String(localized: "Ledge can't file from \(unavailable.count) watched folders right now."))
                        .font(.caption)
                    Text(unavailable.map(\.lastPathComponent).joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                Spacer(minLength: 4)
                // A blocked folder has somewhere to go that Settings isn't.
                if !blocked.isEmpty {
                    Button("Permission…") { PrivacySettings.open() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                SettingsLink { Text("Settings…").font(.caption) }
                    .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
    }

    /// Re-reads liveness and icon for every record currently on the shelf.
    ///
    /// Off the main actor deliberately. Both the liveness check and
    /// `icon(forFile:)` are filesystem reads, run once per record, and a menu
    /// bar icon that does nothing when clicked is the worst failure this view
    /// has.
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
                    isPresent: FileEntry.exists(atPath: record.to.path),
                    icon: NSWorkspace.shared.icon(forFile: record.to.path)
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
                    onOpenPrivacySettings: state.lastErrorOffersPrivacySettings
                        ? { PrivacySettings.open() } : nil) {
            state.clearError()
        }
    }

    /// Names where downloads are going right now, and lets the user change it.
    /// Without this, project mode is invisible: nothing else in the shelf says
    /// which folder the next download will land in.
    private var destinationHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("FILING INTO")
                .sectionLabel()
            Menu {
                Button {
                    state.setActiveProject(nil)
                } label: {
                    Label(defaultDestinationName,
                          systemImage: state.activeProject == nil ? "checkmark" : "")
                }
                ForEach(state.projects) { project in
                    Button {
                        state.setActiveProject(project)
                    } label: {
                        Label(project.name,
                              systemImage: state.activeProject?.id == project.id ? "checkmark" : "")
                    }
                }
                Divider()
                Button("Choose Project…", action: chooseProject)
            } label: {
                Text(state.activeProject?.name ?? defaultDestinationName)
                    .font(.body.weight(.medium))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
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

extension View {
    /// The small, quiet label naming a block of the shelf.
    ///
    /// The uppercasing lives in the string catalog rather than in
    /// `.textCase(.uppercase)`, which uppercases with the non-localised
    /// `String.uppercased()`. Measured on 2026-09-01: that turns Turkish
    /// "Son İndirilenler" into "SON İNDIRILENLER" — a dotless I in a language
    /// that distinguishes the two letters. `uppercased(with: Locale(identifier:
    /// "tr"))` gets it right, but SwiftUI does not call that one, and a view
    /// modifier is the wrong place to be choosing a locale anyway.
    func sectionLabel() -> some View {
        self
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
    }
}
