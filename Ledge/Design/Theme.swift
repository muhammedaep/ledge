import AppKit
import SwiftUI

/// The design's scale, in one place.
///
/// Every number and every literal colour in the interface comes from here. The
/// alternative — each view carrying its own 7s and 12s — is how two surfaces
/// that were drawn to match stop matching, one honest edit at a time.
///
/// What is *not* here: the label hierarchy. Primary, 62% and 38% are macOS's
/// own label colours, and `.primary` / `.secondary` / `.tertiary` produce them
/// in both themes and adapt on their own. Restating them as literals would
/// freeze them.
enum Theme {
    /// The 4pt grid.
    enum Space {
        static let panel: CGFloat = 12
        static let card: CGFloat = 10
        /// Icon to text.
        static let iconGap: CGFloat = 9
        /// Filename to its metadata line. They are one object; anything larger
        /// reads as two.
        static let nameToMeta: CGFloat = 1
        static let rowGap: CGFloat = 3
        static let section: CGFloat = 14
    }

    enum Size {
        static let field: CGFloat = 22
        static let button: CGFloat = 26
        static let popup: CGFloat = 28
        static let row: CGFloat = 46
        static let footer: CGFloat = 38
        static let badge: CGFloat = 32
    }

    enum Radius {
        static let field: CGFloat = 5
        static let row: CGFloat = 7
        static let card: CGFloat = 8
        static let window: CGFloat = 10
        static let panel: CGFloat = 11
    }

    enum Colour {
        /// The four the system has no equivalent for.
        static let chipFill = dynamic(light: white(1, 0.72), dark: white(1, 0.075))
        static let chipBorder = dynamic(light: white(0, 0.07), dark: white(1, 0.07))
        static let fieldFill = dynamic(light: white(1, 1), dark: white(1, 0.06))
        static let fieldBorder = dynamic(light: white(0, 0.14), dark: white(1, 0.14))

        /// Hue is reserved for meaning: blue is actionable, amber is a warning,
        /// red is a rule that will never work.
        static let accent = dynamic(light: srgb(0x0a6cd6), dark: srgb(0x409cff))
        static let amber = dynamic(light: srgb(0x8a5d00), dark: srgb(0xffd60a))
        static let amberFill = dynamic(light: srgb(0xffc400, 0.14), dark: srgb(0xffd60a, 0.10))
        static let red = dynamic(light: srgb(0xc4322a), dark: srgb(0xff6961))
        static let redFill = dynamic(light: srgb(0xff3b30, 0.09), dark: srgb(0xff6961, 0.12))

        /// The badge families — see the type badge. Page, border, label.
        static let badgeDocPage = dynamic(light: srgb(0xfdeceb), dark: srgb(0xff6961, 0.14))
        static let badgeDocBorder = dynamic(light: srgb(0xeec0bc), dark: srgb(0xff6961, 0.28))
        static let badgeDocLabel = dynamic(light: srgb(0xc4544c), dark: srgb(0xef9a92))
        static let badgeImagePage = dynamic(light: srgb(0xeaf3fd), dark: srgb(0x82b4ec, 0.14))
        static let badgeImageBorder = dynamic(light: srgb(0xbcd6f2), dark: srgb(0x82b4ec, 0.28))
        static let badgeImageLabel = dynamic(light: srgb(0x3b74b5), dark: srgb(0x82b4ec))
        static let badgeMoviePage = dynamic(light: srgb(0xf0ebfb), dark: srgb(0xc3a3ef, 0.14))
        static let badgeMovieBorder = dynamic(light: srgb(0xd0c2ee), dark: srgb(0xc3a3ef, 0.28))
        static let badgeMovieLabel = dynamic(light: srgb(0x7a5bc0), dark: srgb(0xc3a3ef))

        /// One neutral in both themes, so a hover never has to know the theme.
        static let hover = Color(white: 0.5, opacity: 0.16)
        static let hoverStrong = Color(white: 0.5, opacity: 0.18)

        /// A colour that answers differently in each theme.
        ///
        /// In Swift rather than an asset catalog on purpose. This target has no
        /// catalog and its project file lists every resource by hand, so adding
        /// one is project-file surgery — and a catalog colour whose name is
        /// wrong does not fail the build, it renders as a placeholder at
        /// runtime. Nobody on this project can see runtime. Here a typo is a
        /// compile error.
        private static func dynamic(light: NSColor, dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            })
        }

        private static func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                    green: CGFloat((hex >> 8) & 0xFF) / 255,
                    blue: CGFloat(hex & 0xFF) / 255,
                    alpha: alpha)
        }

        private static func white(_ value: CGFloat, _ alpha: CGFloat) -> NSColor {
            NSColor(white: value, alpha: alpha)
        }
    }
}

extension View {
    /// 11 semibold, +0.06em, tertiary. The uppercase is in the string, not here
    /// — see the global constraint about Turkish `İ`.
    func sectionLabel() -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(.tertiary)
    }

    /// 10 semibold, +0.05em, tertiary. The field labels inside a rule card.
    func fieldLabel() -> some View {
        font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(.tertiary)
    }

    /// 13 regular, primary. Filenames and controls.
    func rowName() -> some View {
        font(.system(size: 13))
    }

    /// 11 regular. The metadata line, captions, diagnostics.
    ///
    /// The style is a parameter rather than a fixed `.secondary` because a
    /// caller sometimes needs a different one — a stale shelf row's metadata
    /// falls to `.tertiary` — and chaining `.foregroundStyle` onto this helper
    /// does **not** override what it sets. Measured on 2026-09-02 by rendering
    /// both and diffing the bitmaps: a style applied directly to a leaf view
    /// beats one applied to it from further out in the same chain, whichever
    /// comes later in the source. The same trap is waiting in `sectionLabel()`
    /// and `fieldLabel()`, which set `.tertiary` the same way.
    func rowMeta(_ style: AnyShapeStyle = AnyShapeStyle(.secondary)) -> some View {
        font(.system(size: 11)).foregroundStyle(style)
    }

    /// 11 SF Mono, primary. Extensions, name patterns, globs.
    func mono() -> some View {
        font(.system(size: 11, design: .monospaced))
    }

    /// 13 semibold, primary. Window titles and the empty-state headline.
    func titleText() -> some View {
        font(.system(size: 13, weight: .semibold))
    }

    /// 12 regular, primary. Field text and the Organize sheet's list rows.
    func fieldText() -> some View {
        font(.system(size: 12))
    }
}
