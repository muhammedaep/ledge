import AppKit
import SwiftUI

/// Shown in place of the shelf's list when Ledge cannot *read* a watched folder.
///
/// Without it, a declined consent prompt produces an app that looks perfectly
/// healthy in the menu bar and files nothing, forever — the failure has to
/// explain itself somewhere, and this is the only surface the user opens.
///
/// Only for a folder that is there and refuses to be read. A folder that is
/// merely gone (ejected drive, deleted directory) is not a permission problem
/// and gets the shelf's unavailable-folder banner instead; offering Privacy
/// Settings for it would send the user to a dialog that cannot grant anything.
/// The shelf keeps its footer around this view, so Settings and Quit stay
/// reachable while it is up.
struct PermissionView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ledge can't read your \(folderName) folder", systemImage: "lock.fill")
                .font(.headline)

            Text("macOS needs your permission before Ledge can file downloads. Grant access to that folder, then reopen this menu.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Only worth listing when the headline can't name them all.
            if blockedFolders.count > 1 {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(blockedFolders, id: \.self) { folder in
                        Text(folder.path)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Button("Open Privacy Settings", action: openPrivacySettings)
        }
        .padding(16)
        // The width comes from the shelf, which wraps this in the panel that
        // also carries Settings and Quit — this view is the *list* being
        // replaced, not the whole window.
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var blockedFolders: [URL] { state.unreadableFolders }

    private var folderName: String {
        blockedFolders.first?.lastPathComponent ?? String(localized: "Downloads")
    }

    private func openPrivacySettings() {
        PrivacySettings.open()
    }
}

/// Where a blocked folder is granted.
///
/// The pane is Privacy & Security › Files and Folders, where Ledge's own row
/// carries the folder switches. `Privacy_FilesAndFolders` is the anchor the
/// current Settings extension answers to; the pre-Ventura
/// `com.apple.preference.security?Privacy_Files` spelling is not one it
/// advertises any more, and a URL it doesn't recognise opens Settings on
/// whatever pane happens to be last.
///
/// Shared with the shelf's banner, which offers the same route when only some
/// of the watched folders are blocked — one URL, so the two cannot drift.
enum PrivacySettings {
    static func open() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_FilesAndFolders"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
