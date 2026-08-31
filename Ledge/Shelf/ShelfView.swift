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
        }
        .frame(width: 360)
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
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in
            Task {
                await refreshRowStatus()
                await state.refreshFolderStatus()
            }
        }
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

            Text("Recent Downloads")
                .font(.headline)
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
    /// `icon(forFile:)` are filesystem reads, and a record can point at a
    /// volume that is no longer mounted — `AppState.filingRoot` contemplates
    /// exactly that — where a read blocks for the mount timeout rather than
    /// failing fast. Run per visible row on the main actor, that is a menu bar
    /// icon that does nothing when clicked.
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
        ErrorBanner(message: state.lastError, horizontalPadding: 12, topPadding: 8) {
            state.clearError()
        }
    }

    /// Names where downloads are going right now, and lets the user change it.
    /// Without this, project mode is invisible: nothing else in the shelf says
    /// which folder the next download will land in.
    private var destinationHeader: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Filing into:")
                .font(.caption)
                .foregroundStyle(.secondary)
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
