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
/// Both are filesystem reads, done once per visible row, and the shelf has to
/// open the instant the menu bar icon is clicked.
///
/// The stall this actually avoids is an unresponsive *network* mount, where a
/// stat blocks until the mount times out. It is deliberately no longer claimed
/// for "a disconnected volume": a detached local volume was measured answering
/// in 0.0023 s, so for that case this sweep is precautionary rather than
/// load-bearing. Said the old way, the justification was disprovable in thirty
/// seconds — which is an invitation to delete the code it defends.
struct ShelfRow: View {
    let record: MoveRecord
    /// Whether the file was there as of the shelf's last sweep. Drives how the
    /// row *looks*; never the gate on what it *does* — see `isStillThere()`.
    let isPresent: Bool
    /// Nil until the first sweep lands, when a generic symbol stands in.
    let icon: NSImage?
    let onUndo: () -> Void

    @State private var isHovered = false

    /// Where the file went, read as a trail rather than a single folder name.
    ///
    /// `relativeFolder` used to be `to.deletingLastPathComponent().lastPathComponent`,
    /// which for `Downloads/Images/PNG/x.png` said only "PNG" — the least
    /// informative half of the answer, and ambiguous the moment two categories
    /// both subdivide by extension. `record.from` is the folder the file was
    /// found in, so the components below it are exactly the trail Ledge chose.
    ///
    /// Project mode files *outside* `from` on purpose (spec §13), so the prefix
    /// check fails there and the last component is used. That is a fallback,
    /// not a bug: the destination header already names the project.
    private var destinationTrail: String {
        let folder = record.to.deletingLastPathComponent().standardizedFileURL
        let root = record.from.standardizedFileURL
        let parts = folder.pathComponents
        let rootParts = root.pathComponents
        guard parts.count > rootParts.count,
              Array(parts.prefix(rootParts.count)) == rootParts
        else { return folder.lastPathComponent }
        return parts.dropFirst(rootParts.count).joined(separator: " · ")
    }

    /// When the file was filed.
    ///
    /// Not `Text(_:format: .relative(presentation: .numeric))`, which is what
    /// this was: a record seconds old renders as **"in 0 seconds"** — the wrong
    /// unit, rounded to zero, and pointing into the future. Seen on the first
    /// real run, on every fresh row.
    ///
    /// Anything under a minute is "now", which is both true and the only phrase
    /// that does not go stale while it is being read. Above that the formatter
    /// has a unit worth naming.
    ///
    /// Computed rather than bound, so it no longer re-renders every second for
    /// a panel that is usually closed; the shelf recomputes when it opens,
    /// which is the only moment anyone can see it.
    private var filedWhen: String {
        let age = Date.now.timeIntervalSince(record.date)
        guard age >= 60 else { return String(localized: "now") }
        return Self.relative.localizedString(for: record.date, relativeTo: .now)
    }

    private static let relative: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

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
    ///
    /// `FileEntry.exists` rather than `fileExists` so this agrees with what the
    /// mover and undo mean by "there": a dangling symlink is an entry the rest
    /// of the app will happily move, and refusing to drag or reveal it here
    /// would be the row disagreeing with its own undo button.
    private func isStillThere() -> Bool {
        isPresent && FileEntry.exists(atPath: record.to.path)
    }

    var body: some View {
        HStack(spacing: 10) {
            fileIcon
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(record.originalName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // A stale row's *name* is struck through, not its whole
                    // body: the name is the part that no longer points at
                    // anything, and striking the subtitle would cross out the
                    // sentence explaining why.
                    .strikethrough(!isPresent, color: .secondary)
                Text(isPresent ? destinationTrail : String(localized: "Moved or deleted"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }

            Spacer(minLength: 8)

            Text(filedWhen)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .monospacedDigit()

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Undo this move"))
            .disabled(!isPresent)
            // Dimmed rather than hidden when the pointer is elsewhere. Fully
            // hiding it would make undo undiscoverable — you cannot hover for
            // a control you do not know is there — and would take it away from
            // anyone driving the app without a pointer.
            .opacity(isHovered ? 1 : 0.4)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(isHovered ? 0.08 : 0))
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .opacity(isPresent ? 1 : 0.5)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.12), value: isHovered)
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
                .scaledToFit()
        } else {
            Image(systemName: "doc")
                .resizable()
                .scaledToFit()
                .padding(4)
                .foregroundStyle(.secondary)
        }
    }
}
