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
            }

            Section("Watched folders") {
                ForEach(preferences.watchedFolders, id: \.self) { folder in
                    HStack {
                        Text(folder.path).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button(role: .destructive) {
                            state.removeWatchedFolder(folder)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
                        // Nothing left to watch would be an app with no
                        // purpose and no sign of why.
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
                        .foregroundStyle(.secondary)
                }
                ForEach(state.projects) { project in
                    HStack {
                        TextField("Name", text: Binding(
                            get: { project.name },
                            set: { rename(project, to: $0) }
                        ))
                        .textFieldStyle(.plain)

                        Text(project.folder.path)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.head)

                        Button(role: .destructive) {
                            state.updateProjects(state.projects.filter { $0.id != project.id })
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.borderless)
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
    }

    private func rename(_ project: Project, to newName: String) {
        var updated = state.projects
        guard let index = updated.firstIndex(where: { $0.id == project.id }) else { return }
        updated[index].name = newName
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
