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

    var body: some View {
        // A watched folder Ledge cannot read means nothing will ever be filed,
        // so the shelf would be a permanently empty list with no explanation.
        // The reason takes its place until access is granted.
        if state.hasFolderAccess {
            shelf
        } else {
            PermissionView()
        }
    }

    private var shelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            destinationHeader

            errorBanner

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

            Divider()

            HStack {
                Button("Organize Now…") { showingOrganize = true }
                Spacer()
                SettingsLink { Image(systemName: "gearshape") }
                    .buttonStyle(.borderless)
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
        .frame(width: 360)
        .sheet(isPresented: $showingOrganize) {
            OrganizeSheet()
                .environment(state)
        }
        // Fires when the shelf appears, and again whenever the record list
        // changes under it.
        .task(id: state.recentRecords.map(\.id)) {
            await refreshRowStatus()
        }
        // A second, independent trigger, because the first depends on something
        // this session could not verify: whether SwiftUI re-runs `.task` each
        // time a `MenuBarExtra(style: .window)` popover is shown, or creates the
        // content once and keeps it alive. The popover's panel becomes key when
        // it opens, so this covers the case where the view survives and `.task`
        // does not re-run. Either trigger alone is enough; both are cheap.
        .onReceive(NotificationCenter.default.publisher(
            for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await refreshRowStatus() }
        }
    }

    /// Re-reads liveness and icon for every record currently on the shelf.
    ///
    /// Off the main actor deliberately. Both `fileExists` and
    /// `icon(forFile:)` are filesystem reads, and a record can point at a
    /// volume that is no longer mounted — `AppState.filingRoot` contemplates
    /// exactly that — where a read blocks for the mount timeout rather than
    /// failing fast. Run per visible row on the main actor, that is a menu bar
    /// icon that does nothing when clicked.
    private func refreshRowStatus() async {
        let records = state.recentRecords
        rowStatus = await Task.detached(priority: .userInitiated) {
            var status: [UUID: RowStatus] = [:]
            for record in records {
                status[record.id] = RowStatus(
                    isPresent: FileManager.default.fileExists(atPath: record.to.path),
                    icon: NSWorkspace.shared.icon(forFile: record.to.path)
                )
            }
            return status
        }.value
    }

    /// `AppState` records five different failures and, until now, showed none
    /// of them. For an app whose whole job is moving the user's files, a failed
    /// undo that reports nothing is worse than one that never happened.
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
            .padding(.horizontal, 12)
            .padding(.top, 8)
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
        if !choice.wasAlreadyKnown {
            state.updateProjects(choice.projects)
        }
        state.setActiveProject(choice.project)
    }
}
