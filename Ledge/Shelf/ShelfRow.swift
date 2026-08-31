import AppKit
import SwiftUI
import LedgeCore

/// One filed download: its icon, its name, the folder it went into, and the
/// undo arrow.
///
/// The row is also the drag source — the whole point of the shelf is that the
/// file stays reachable, so dragging the row hands the real file to whatever
/// app is underneath.
///
/// `isPresent` and `icon` are handed in by `ShelfView` rather than read here.
/// Both are filesystem reads, and a record can point at a disconnected volume —
/// `AppState.filingRoot` explicitly contemplates one — so doing them in `body`,
/// once per visible row, on the main actor, would block the popover for the
/// mount timeout: the user clicks the menu bar icon and nothing opens.
struct ShelfRow: View {
    let record: MoveRecord
    /// Whether the file was there as of the shelf's last sweep. Drives how the
    /// row *looks*; never the gate on what it *does* — see `isStillThere()`.
    let isPresent: Bool
    /// Nil until the first sweep lands, when a generic symbol stands in.
    let icon: NSImage?
    let onUndo: () -> Void

    private var relativeFolder: String {
        record.to.deletingLastPathComponent().lastPathComponent
    }

    /// Whether the file is there *now*, re-read at gesture time rather than
    /// trusted from `isPresent`, which may be a sweep out of date.
    ///
    /// This check is load-bearing, and that is measured rather than assumed:
    /// `NSItemProvider(contentsOf:)` returns a perfectly good provider for a
    /// file that does not exist. It derives its type from the path extension
    /// and never stats the file — checked on 2026-09-01 against a missing file
    /// with a known extension, with no extension, with an unknown extension,
    /// and with no parent directory at all. Every one produced a non-nil
    /// provider advertising `public.file-url`. So nothing downstream catches a
    /// stale row; without this the drag hands the drop target a dangling URL.
    /// Do not simplify it away on the reasonable-looking grounds that the
    /// initializer returns nil for a missing file. It does not.
    ///
    /// `isPresent` short-circuits it, which also keeps the common stale case
    /// from touching the filesystem on the main actor at all.
    private func isStillThere() -> Bool {
        isPresent && FileManager.default.fileExists(atPath: record.to.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            fileIcon
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.originalName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(isPresent ? relativeFolder : String(localized: "Moved or deleted"))
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
            .disabled(!isPresent)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .contentShape(Rectangle())
        .opacity(isPresent ? 1 : 0.45)
        .onDrag {
            guard isStillThere() else { return NSItemProvider() }
            // Optional in signature only. The empty provider is not a second
            // line of defence — it is what an unconstructible provider would
            // degrade to, and it carries nothing.
            return NSItemProvider(contentsOf: record.to) ?? NSItemProvider()
        }
        .onTapGesture {
            // A stale row does nothing. Revealing it would open the parent
            // folder, which is precisely where the file no longer is.
            guard isStillThere() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([record.to])
        }
    }

    @ViewBuilder
    private var fileIcon: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
        } else {
            Image(systemName: "doc")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.secondary)
        }
    }
}
