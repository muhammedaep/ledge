import AppKit
import SwiftUI
import LedgeCore

/// The menu bar panel: where downloads are being filed, what was filed
/// recently, and the handful of actions that operate on the whole app.
struct ShelfView: View {
    @Environment(AppState.self) private var state
    @State private var showingOrganize = false

    var body: some View {
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
                            // `undo` is async, so the row's synchronous button
                            // action hands it to a task rather than awaiting it.
                            ShelfRow(record: record) {
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

    private var defaultDestinationName: String {
        state.preferences.watchedFolders.first?.lastPathComponent
            ?? String(localized: "Downloads")
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
        let project = Project(folder: url)
        state.updateProjects(state.projects + [project])
        state.setActiveProject(project)
    }
}
