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
/// `isPresent` is handed in by `ShelfView` rather than read here. It is a
/// filesystem read, done once per visible row, and the shelf has to open the
/// instant the menu bar icon is clicked.
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
    /// The project this row was filed under, when it was filed under one.
    /// Nil for everything filed into a watched folder.
    let projectName: String?
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
        HStack(spacing: Theme.Space.iconGap) {
            TypeBadge(fileExtension: record.to.pathExtension)
                .opacity(isPresent ? 1 : 0.35)
                .grayscale(isPresent ? 0 : 1)

            VStack(alignment: .leading, spacing: Theme.Space.nameToMeta) {
                Text(record.originalName)
                    .rowName()
                    .foregroundStyle(isPresent
                                     ? AnyShapeStyle(.primary)
                                     : AnyShapeStyle(Theme.Colour.textSecondary))
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Destination, subdivision and time are peers in one line that
                // truncates from the tail, so time degrades first — it is the
                // least load-bearing of the three. The rejected alternative gave
                // time its own right-aligned slot, which put three claims on one
                // edge and lost the argument to Turkish.
                Text(metadata)
                    .rowMeta(isPresent
                             ? AnyShapeStyle(Theme.Colour.textSecondary)
                             : AnyShapeStyle(Theme.Colour.textTertiary))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .background(
                        Circle().fill(isHovered ? Theme.Colour.hoverStrong : Color.clear)
                    )
            }
            .buttonStyle(.plain)
            // Secondary at rest, primary on hover. What hover changes is
            // emphasis, never existence: this is a real focusable button with a
            // focus ring, and someone driving the app from the keyboard must be
            // able to reach it.
            .foregroundStyle(isHovered
                             ? AnyShapeStyle(.primary)
                             : AnyShapeStyle(Theme.Colour.textSecondary))
            .opacity(isPresent ? 1 : 0.3)
            .help(String(localized: "Undo this move"))
            .disabled(!isPresent)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        // The chip. A present row is an object you can pick up; a stale one
        // loses its fill, its border and its shadow, because flat reads as
        // inert and that is exactly what it is.
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(isPresent ? Theme.Colour.chipFill : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .stroke(isPresent ? Theme.Colour.chipBorder : Color.clear, lineWidth: 1)
        }
        // The token, not the numbers: these were right, and staying right
        // means changing with the rest of the scale rather than beside it.
        // A stale row keeps the geometry and drops the colour.
        .shadow(color: .black.opacity(isPresent ? Theme.Shadow.row.opacity : 0),
                radius: Theme.Shadow.row.radius, y: Theme.Shadow.row.y)
        .contentShape(Rectangle())
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

    /// Destination, subdivision and time in one line — or, when the file is
    /// gone, the status in the destination's place.
    ///
    /// `destinationTrail` already joins the folders below the watched root with
    /// `·`, so appending time with the same separator keeps one grammar for the
    /// whole line rather than two.
    private var metadata: String {
        guard isPresent else {
            return "\(String(localized: "Moved or deleted")) · \(filedWhen)"
        }
        return "\(projectName ?? destinationTrail) · \(filedWhen)"
    }
}
