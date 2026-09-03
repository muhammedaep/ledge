import AppKit
import LedgeCore
import SwiftUI

/// Settings › General: whether Ledge files at all, where it watches, where it
/// can file to, and how much of the journal the shelf shows.
struct GeneralPane: View {
    @Environment(AppState.self) private var state

    var body: some View {
        @Bindable var preferences = state.preferences

        Form {
            Section {
                Toggle("File downloads automatically", isOn: $preferences.automaticFilingEnabled)
                    .onChange(of: preferences.automaticFilingEnabled) { _, enabled in
                        enabled ? state.startWatching() : state.stopWatching()
                    }
                Toggle("Launch at login", isOn: $preferences.launchAtLogin)

                Picker("Appearance", selection: $preferences.appearance) {
                    Text("System").tag(AppearanceSetting.system)
                    Text("Light").tag(AppearanceSetting.light)
                    Text("Dark").tag(AppearanceSetting.dark)
                    Text("Black").tag(AppearanceSetting.black)
                }
                .onChange(of: preferences.appearance) { _, choice in
                    Theme.apply(choice)
                }
            }

            Section("Watched folders") {
                ForEach(preferences.watchedFolders, id: \.self) { folder in
                    HStack {
                        // This is where a folder that has gone is meant to be
                        // dealt with, so it has to be visible here rather than
                        // only in the shelf's banner.
                        if state.folderStatus[folder] == .missing {
                            Image(systemName: "externaldrive.trianglebadge.exclamationmark")
                                .foregroundStyle(.orange)
                                .help(String(localized: "This folder isn't there right now."))
                        } else if state.folderStatus[folder] == .unreadable {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.orange)
                                .help(String(localized: "Ledge doesn't have permission to read this folder."))
                        }

                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .foregroundStyle(state.folderStatus[folder] == .readable
                                             ? .primary : .secondary)
                        Spacer()
                        Button(role: .destructive) {
                            state.removeWatchedFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        // Nothing left to watch would be an app with no
                        // purpose and no sign of why. To replace the last
                        // folder — including one that has gone missing — add
                        // the new one first, then remove this.
                        .disabled(preferences.watchedFolders.count == 1)
                    }
                }
                Button("Add Folder…", action: pickFolder)
            }

            // Removing the active project has to go through
            // `AppState.updateProjects`, which resets the destination back to
            // the watched folder — otherwise filing would keep aiming at a
            // project the user just deleted.
            Section("Projects") {
                if state.projects.isEmpty {
                    Text("No projects yet. Add one here, or from the shelf's destination menu.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colour.textSecondary)
                }
                ForEach(state.projects) { project in
                    ProjectRow(project: project) { renamed in
                        rename(project, to: renamed)
                    } remove: {
                        state.updateProjects(state.projects.filter { $0.id != project.id })
                    }
                }
                Button("Add Project…", action: addProject)
            }

            Section {
                Stepper("Keep \(preferences.shelfSize) items on the shelf",
                        value: $preferences.shelfSize, in: 3...50)
                    .onChange(of: preferences.shelfSize) {
                        // The journal is trimmed to this size when it is read,
                        // so without a re-read the shelf keeps showing the old
                        // count until the next file is filed.
                        Task { await state.reloadShelf() }
                    }
            }
        }
        .formStyle(.grouped)
        // Same reason as the Rules list: the grouped form's own ground is the
        // system's grey, and the window's is not.
        .scrollContentBackground(.hidden)
    }

    /// Applies a finished rename. `Project.renamed` decides what a blank name
    /// means — in LedgeCore, where it is tested — rather than this pane storing
    /// whatever was typed.
    private func rename(_ project: Project, to newName: String) {
        var updated = state.projects
        guard let index = updated.firstIndex(where: { $0.id == project.id }) else { return }
        let renamed = updated[index].renamed(to: newName)
        guard renamed != updated[index] else { return }   // nothing changed: no write
        updated[index] = renamed
        state.updateProjects(updated)
    }

    private func pickFolder() {
        guard let url = chooseDirectory() else { return }
        state.addWatchedFolder(url)
    }

    private func addProject() {
        guard let url = chooseDirectory() else { return }
        // Appending unconditionally would mint a second, indistinguishable
        // project for a folder the user has already added. Deciding whether
        // two URLs name the same folder is `Project.choosing`'s job, in
        // LedgeCore, where it is tested — the pane only saves the result.
        state.updateProjects(Project.choosing(url, in: state.projects).projects)
    }

    private func chooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        // Ledge is an accessory app (LSUIElement); the Settings window makes it
        // active, but not reliably so if this pane is reached while another app
        // is frontmost.
        NSApplication.shared.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
}

/// One project: rename in place, or remove.
///
/// The rename is held locally and committed on Return or when focus leaves,
/// rather than on every keystroke. Committing per keystroke re-encoded and
/// rewrote `projects.json` for every character typed, and — worse — ran the
/// blank-name rule mid-word, so clearing the field to retype snapped the name
/// back to the folder's before the user had typed anything.
private struct ProjectRow: View {
    let project: Project
    let rename: (String) -> Void
    let remove: () -> Void

    @State private var draft: String
    @FocusState private var isEditing: Bool

    init(project: Project, rename: @escaping (String) -> Void, remove: @escaping () -> Void) {
        self.project = project
        self.rename = rename
        self.remove = remove
        _draft = State(initialValue: project.name)
    }

    var body: some View {
        HStack {
            TextField("Name", text: $draft)
                .textFieldStyle(.plain)
                .focused($isEditing)
                .onSubmit(commit)
                .onChange(of: isEditing) { _, editing in
                    if !editing { commit() }
                }
                // Someone else can rename this project — the shelf's menu, or a
                // second Settings window — while this row is on screen.
                .onChange(of: project.name) { _, newName in
                    if !isEditing { draft = newName }
                }

            Text(project.folder.path)
                .font(.caption)
                .foregroundStyle(Theme.Colour.textSecondary)
                .lineLimit(1)
                .truncationMode(.head)

            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private func commit() {
        rename(draft)
        // Show what was actually stored, which is not always what was typed:
        // a blank name falls back to the folder's.
        draft = project.renamed(to: draft).name
    }
}
