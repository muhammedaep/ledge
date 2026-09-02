import SwiftUI
import LedgeCore

/// The drawn page a shelf row carries in place of the macOS file icon.
///
/// This is a real loss, accepted knowingly: a Sketch document stops looking
/// like a Sketch document. What it buys is a row that reads as one designed
/// object in both themes, at one size, with a colour that means something.
///
/// The colour follows the file's kind, never the category it was filed into —
/// see `FileKind`.
struct TypeBadge: View {
    let fileExtension: String

    private var kind: FileKind { FileKind.of(extension: fileExtension) }

    /// The page fill, its border, and the label — one triple per family.
    ///
    /// `.other` deliberately borrows the chip's own fill and border rather than
    /// inventing a fourth hue. The design draws only three families; a neutral
    /// for everything else is this app's answer, not the design's, and it is
    /// the one that adds no meaning where none was intended.
    private var palette: (page: Color, border: Color, label: Color) {
        switch kind {
        case .image:
            return (Theme.Colour.badgeImagePage, Theme.Colour.badgeImageBorder, Theme.Colour.badgeImageLabel)
        case .movie:
            return (Theme.Colour.badgeMoviePage, Theme.Colour.badgeMovieBorder, Theme.Colour.badgeMovieLabel)
        case .document:
            return (Theme.Colour.badgeDocPage, Theme.Colour.badgeDocBorder, Theme.Colour.badgeDocLabel)
        case .other:
            return (Theme.Colour.chipFill, Theme.Colour.chipBorder, Color.secondary)
        }
    }

    /// Up to four characters, uppercased for the drawing only.
    ///
    /// The extension arrives raw from `URL.pathExtension`, which promises
    /// nothing about its characters — macOS allows non-ASCII filenames, so
    /// this is not guaranteed to be Latin text. `uppercased()` is used anyway
    /// because this label is decorative and `accessibilityHidden`: for a
    /// non-Latin extension the case-map may read oddly, but nothing reads it,
    /// so nothing breaks.
    ///
    /// This is not a licence to use `uppercased()` elsewhere. Anywhere the
    /// user reads a sentence, the uppercase belongs in the string catalog —
    /// SwiftUI and Foundation fold `String.uppercased()` without a locale,
    /// and it turns the Turkish `İ` into a dotless `I`. This project has hit
    /// that twice.
    private var label: String {
        String(fileExtension.prefix(4)).uppercased()
    }

    var body: some View {
        ZStack {
            PageShape()
                .fill(palette.page)
            PageShape()
                .stroke(palette.border, lineWidth: 1)
            if !label.isEmpty {
                Text(label)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(palette.label)
                    .offset(y: 9)
            }
        }
        .frame(width: Theme.Size.badge, height: Theme.Size.badge)
        .accessibilityHidden(true)
    }
}

/// A page with its top-right corner turned down, on the design's 32pt grid.
///
/// The coordinates are the board's own, divided by 32 and multiplied by the
/// rect, so the shape survives being drawn at another size without anyone
/// re-deriving it.
private struct PageShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 32
        var path = Path()
        path.move(to: CGPoint(x: 7 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 19 * s, y: 3 * s))
        path.addLine(to: CGPoint(x: 25 * s, y: 9 * s))
        path.addLine(to: CGPoint(x: 25 * s, y: 29 * s))
        path.addLine(to: CGPoint(x: 7 * s, y: 29 * s))
        path.closeSubpath()
        return path
    }
}
