import AppKit
import SwiftUI
import LedgeCore

/// One filed download: its icon, its name, the folder it went into, and the
/// undo arrow.
///
/// The row is also the drag source — the whole point of the shelf is that the
/// file stays reachable, so dragging the row hands the real file to whatever
/// app is underneath.
struct ShelfRow: View {
    let record: MoveRecord
    let onUndo: () -> Void

    /// A record outlives the file it describes: the user can move, rename or
    /// delete it in Finder. A stale row is dimmed, undraggable, its undo
    /// disabled, and inert to a tap — there is nowhere useful to send the user,
    /// because the parent folder is precisely where the file no longer is.
    private var exists: Bool {
        FileManager.default.fileExists(atPath: record.to.path)
    }

    private var relativeFolder: String {
        record.to.deletingLastPathComponent().lastPathComponent
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: record.to.path))
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.originalName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(exists ? relativeFolder : String(localized: "Moved or deleted"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Text(record.date, format: .relative(presentation: .numeric))
                .font(.caption)
                .foregroundStyle(.tertiary)

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Undo this move"))
            .disabled(!exists)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .opacity(exists ? 1 : 0.45)
        .onDrag {
            guard exists, let provider = NSItemProvider(contentsOf: record.to) else {
                return NSItemProvider()
            }
            return provider
        }
        .onTapGesture {
            guard exists else { return }
            NSWorkspace.shared.activateFileViewerSelecting([record.to])
        }
    }
}
