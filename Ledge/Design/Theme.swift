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
        /// The destination chip.
        ///
        /// A deliberate departure, asked for directly: the design source says
        /// `.pop { height: 28px }` and this is 34.
        ///
        /// 28 read as slighter than the rows it leads. 44 — a row's own height
        /// — was worse the other way: a row spends its 44 on a 32pt badge,
        /// while the chip holds 13pt text, so the same number leaves it mostly
        /// empty. 34 is the middle, and it is the one that was actually seen:
        /// the 44 was judged against a build where a misplaced frame meant the
        /// value never reached the layer that draws the box.
        static let popup: CGFloat = 34
        static let row: CGFloat = 46
        static let footer: CGFloat = 38
        static let badge: CGFloat = 32
    }

    /// The design's `box-shadow`s, converted once.
    ///
    /// CSS blur is roughly twice SwiftUI's radius, so `0 1px 2px` becomes
    /// `radius: 1, y: 1`. Doing that arithmetic at each call site is how four
    /// surfaces end up with four different ideas of the same shadow — which is
    /// what happened here before this existed.
    enum Shadow {
        struct Spec {
            let opacity: Double
            let radius: CGFloat
            let y: CGFloat
        }

        /// `.pop` — `0 .5px 1.5px rgba(0,0,0,.08)`
        static let chip = Spec(opacity: 0.08, radius: 0.75, y: 0.5)
        /// `.row` — `0 1px 2px rgba(0,0,0,.06)`
        static let row = Spec(opacity: 0.06, radius: 1, y: 1)
        /// `.field` — `0 .5px 1px rgba(0,0,0,.05)`
        static let field = Spec(opacity: 0.05, radius: 0.5, y: 0.5)
        /// `.seg .on` — `0 .5px 2px rgba(0,0,0,.18)`
        static let segment = Spec(opacity: 0.18, radius: 1, y: 0.5)
        /// The sheet's buttons.
        static let button = Spec(opacity: 0.10, radius: 0.5, y: 0.5)
    }

    enum Radius {
        static let field: CGFloat = 5
        /// Every filled or bordered pill in the design: the chip, the segment
        /// track, the diagnostics, the sheet's buttons.
        static let pill: CGFloat = 6
        static let row: CGFloat = 7
        static let card: CGFloat = 8
        static let window: CGFloat = 10
        static let panel: CGFloat = 11
    }

    enum Colour {
        /// The four the system has no equivalent for.
        /// `--tx2` and `--tx3`, taken from the design source rather than left
        /// to `.secondary` and `.tertiary`.
        ///
        /// The system's semantics are close but thinner: `.secondary` renders
        /// the metadata line at about 50% where the design asks for 62%, and
        /// `.tertiary` dims a stale row to roughly 25% against the design's
        /// 38%. Read side by side with the boards, ours was the paler of the
        /// two and the second line under each filename was the first thing to
        /// suffer for it.
        static let textSecondary = dynamic(light: srgb(60, 60, 67, 0.62),
                                           dark: srgb(235, 235, 245, 0.58))
        static let textTertiary = dynamic(light: srgb(60, 60, 67, 0.38),
                                          dark: srgb(235, 235, 245, 0.32))

        /// `.seg` — the subdivision control's track, rgba(127,127,127,.14).
        /// Grey rather than a themed white or black: it has to sit on the card
        /// in both appearances without inverting.
        static let segmentTrack = Color(nsColor: NSColor(white: 0.5, alpha: 0.14))

        /// `--chipbg` / `--chipbd`. One surface for the destination chip and
        /// the rows both — the design shares them deliberately, and inventing a
        /// second pair to "separate" them was a guess that the source does not
        /// support.
        /// `--chipbg`, except on black.
        ///
        /// Dark keeps the source's 0.075 exactly. Black raises it to 0.10,
        /// which is not a second opinion about the design: 7.5% white reads as
        /// a card against `rgba(43,43,46,.78)` and all but disappears against
        /// an actual black, so the ground change drags this one with it.
        @MainActor static var chipFill: Color {
            Theme.isBlack
                ? Color(nsColor: white(1, 0.10))
                : dynamic(light: white(1, 0.72), dark: white(1, 0.075))
        }
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
        ///
        /// The dark values are the design's own rgba triples, not the label
        /// hue re-used at a guessed alpha. Three things were wrong here: every
        /// border sat at 0.28 where the design asks 0.45–0.5, the fills were a
        /// step light, and the document family was built from the semantic
        /// `red` (255,105,97) rather than its own coral (240,150,140) — a
        /// different hue, not a different opacity.
        static let badgeDocPage = dynamic(light: srgb(0xfdeceb), dark: srgb(240, 150, 140, 0.16))
        static let badgeDocBorder = dynamic(light: srgb(0xeec0bc), dark: srgb(240, 150, 140, 0.45))
        static let badgeDocLabel = dynamic(light: srgb(0xc4544c), dark: srgb(0xef9a92))
        static let badgeImagePage = dynamic(light: srgb(0xeaf3fd), dark: srgb(120, 170, 235, 0.18))
        static let badgeImageBorder = dynamic(light: srgb(0xbcd6f2), dark: srgb(120, 170, 235, 0.50))
        static let badgeImageLabel = dynamic(light: srgb(0x3b74b5), dark: srgb(0x82b4ec))
        static let badgeMoviePage = dynamic(light: srgb(0xf0ebfb), dark: srgb(190, 150, 240, 0.16))
        static let badgeMovieBorder = dynamic(light: srgb(0xd0c2ee), dark: srgb(190, 150, 240, 0.45))
        static let badgeMovieLabel = dynamic(light: srgb(0x7a5bc0), dark: srgb(0xc3a3ef))

        /// There is deliberately no token for the panel's own fill.
        ///
        /// The design gives `.panel` `rgba(246,245,243,.82)` with a 36px blur,
        /// which is how the web imitates macOS vibrancy; the shelf takes a
        /// system material instead, which is the real thing and behaves over
        /// any wallpaper (spec §8.2). Its drop shadow and hairline come from
        /// the panel window, not from us. An audit reading the stylesheet will
        /// score all three as missing — they are answered here, not absent.
        ///
        /// What Ledge paints over the panel's material.
        ///
        /// Nothing in light and nothing in Dark — there the material and the
        /// design's own `rgba(43,43,46,.78)` do the work. Black paints an
        /// actual black over it. macOS has one dark appearance, so a dynamic
        /// colour cannot tell the two apart; `Theme.isBlack` is that fact
        /// made explicit rather than hidden in a colour closure.
        @MainActor static var panelGround: Color {
            Theme.isBlack ? Color(nsColor: white(0, 0.90)) : .clear
        }

        /// The Settings window's ground: the design's `#f2f0ef` / `#2d2b2e`,
        /// or black when Black is chosen.
        @MainActor static var windowGround: Color {
            Theme.isBlack
                ? Color(nsColor: white(0, 1))
                : dynamic(light: srgb(0xf2f0ef), dark: srgb(0x2d2b2e))
        }

        /// `--sep`. The hairline under the shelf's footer and the Settings
        /// toolbar. Both drew a system `Divider()`, which is not this colour.
        static let separator = dynamic(light: white(0, 0.09), dark: white(1, 0.10))

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

        private static func srgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                 _ alpha: CGFloat) -> NSColor {
            NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: alpha)
        }
    }
}

/// A plain glyph button that darkens with `Theme.Colour.hover` under the
/// pointer — the one neutral spec §4 gives every hover state, applied here so
/// a control that shows nothing at rest isn't also invisible to a mouse that
/// has found it. Existence never depends on hover, only emphasis: nothing
/// here disables the button or hides the glyph when the pointer moves away,
/// the same rule the shelf's undo button follows.
struct HoverGlyphButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        HoverGlyphButtonBody(configuration: configuration, cornerRadius: cornerRadius)
    }
}

/// Split out from `HoverGlyphButtonStyle` because a `ButtonStyle` is handed a
/// fresh `Configuration` value on every call; `isHovered` needs a `View` to
/// live in so `@State` can hold it across redraws.
private struct HoverGlyphButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(isHovered ? Theme.Colour.hover : Color.clear)
            }
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// 11 semibold, +0.06em, tertiary. The uppercase is in the string, not here
    /// — see the global constraint about Turkish `İ`.
    func sectionLabel() -> some View {
        font(.system(size: 11, weight: .semibold))
            .tracking(0.66)
            .foregroundStyle(Theme.Colour.textTertiary)
    }

    /// 10 semibold, +0.05em, tertiary. The field labels inside a rule card.
    func fieldLabel() -> some View {
        font(.system(size: 10, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(Theme.Colour.textTertiary)
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
    func rowMeta(
        _ style: AnyShapeStyle = AnyShapeStyle(Theme.Colour.textSecondary)
    ) -> some View {
        // 11/14 in the source. The explicit line height matters: left to
        // SwiftUI's default the metadata sat a point lower and the two lines
        // stopped reading as one object.
        font(.system(size: 11)).lineSpacing(0).foregroundStyle(style)
    }

    /// 11 SF Mono, primary. Extensions, name patterns, globs.
    func mono() -> some View {
        font(.system(size: 11, design: .monospaced))
    }

    /// 11 medium. The small action inside a banner or a header — `Choose
    /// Folder Again…`, `Open Privacy Settings`, `End`. One number, three
    /// files, before this: exactly the shape that belongs here rather than
    /// staying inline at each call site. Never sets a colour — every call
    /// site still picks its own (amber for a warning, accent for an
    /// in-context action) — so chaining `.foregroundStyle` after this one
    /// works normally; it isn't in the `rowMeta()`/`sectionLabel()`/
    /// `fieldLabel()` family that traps that chain.
    func actionLink() -> some View {
        font(.system(size: 11, weight: .medium))
    }

    /// 13 semibold, primary. Window titles and the empty-state headline.
    func titleText() -> some View {
        font(.system(size: 13, weight: .semibold))
    }

    /// One of the design's shadows. Named `themeShadow` rather than
    /// overloading `shadow`, so a call site says which of the two it meant.
    func themeShadow(_ spec: Theme.Shadow.Spec) -> some View {
        shadow(color: .black.opacity(spec.opacity), radius: spec.radius, y: spec.y)
    }

    /// The destination's name in the shelf's chip. The design gives it the
    /// panel's own 13pt — same as a row name — so this exists only to say that
    /// out loud after 15pt was tried and was not what the source says.
    func destinationName() -> some View {
        font(.system(size: 13))
    }

    /// 12 regular, primary. Field text and the Organize sheet's list rows.
    func fieldText() -> some View {
        font(.system(size: 12))
    }
}

extension Theme {
    /// Applies the user's appearance choice to the whole app.
    ///
    /// Set on the application rather than per window, because both the shelf's
    /// panel and the Settings window have to follow it. Nothing else needs to
    /// change: every colour in this file resolves through
    /// `appearance.bestMatch(from: [.aqua, .darkAqua])`, so the palette follows
    /// from this single assignment. `nil` hands control back to the system.
    /// Whether the Black appearance is the one in force.
    ///
    /// Read by the three tokens that differ between Dark and Black. It has to
    /// live here because macOS has exactly two appearances and both of those
    /// settings map onto `darkAqua` — no dynamic colour can see the
    /// difference, so something has to hold it.
    @MainActor private(set) static var isBlack = false

    @MainActor static func apply(_ setting: AppearanceSetting) {
        isBlack = setting == .black
        NSApplication.shared.appearance = switch setting {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark, .black: NSAppearance(named: .darkAqua)
        }
    }
}

/// The design's `.pop` — a destination chip that opens something.
///
/// A `Button`, never a SwiftUI `Menu`. A macOS `Menu` owns how its label draws
/// and how far it takes clicks, and it discards a background, border, shadow
/// or trailing control given to it inside that label, sizes itself to its
/// text, takes clicks only where the text is, and keeps the system control's
/// height. Four separate defects, each fixable by moving one modifier in or
/// out, and each fix breaking another. This exists so that is solved once
/// rather than per surface.
struct ChipButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.accent)

                // No breadcrumb parent: the design shows `Downloads ▸ Sorted`
                // and this app has no `Sorted` — that half of the boards was
                // dropped on purpose, so the leading segment would always be
                // empty. Added back only if a second level ever exists.
                Text(title)
                    .destinationName()
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Theme.Colour.accent)
                    )
            }
            .padding(.leading, 9)
            .padding(.trailing, 7)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.popup)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(Theme.Colour.chipFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .stroke(Theme.Colour.chipBorder, lineWidth: 1)
            }
            .themeShadow(Theme.Shadow.chip)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// A chip's frame in the window, reported up so a menu can hang off it.
struct ChipFrame: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

/// Holds a menu's closures. `NSMenuItem` takes a target and a selector, so a
/// closure needs an object to live on; the tag is the index.
@MainActor final class MenuActions: NSObject {
    var handlers: [Int: () -> Void] = [:]

    @objc func fire(_ sender: NSMenuItem) {
        handlers[sender.tag]?()
    }

    /// Builds a menu from titles and closures, and hangs it under `chipFrame`.
    ///
    /// The flip is not optional: SwiftUI's global space has its origin at the
    /// top left and an AppKit content view has its own at the bottom left.
    func show(_ items: [(title: String, checked: Bool, run: () -> Void)],
              separatorBefore: Int? = nil,
              under chipFrame: CGRect,
              in window: NSWindow?) {
        let menu = NSMenu()
        handlers.removeAll()
        for (offset, item) in items.enumerated() {
            if offset == separatorBefore { menu.addItem(.separator()) }
            let entry = NSMenuItem(title: item.title,
                                   action: #selector(fire(_:)),
                                   keyEquivalent: "")
            entry.target = self
            entry.tag = offset
            entry.state = item.checked ? .on : .off
            handlers[offset] = item.run
            menu.addItem(entry)
        }
        guard let content = window?.contentView, chipFrame != .zero else {
            menu.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
            return
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: chipFrame.minX,
                               y: content.bounds.height - chipFrame.maxY),
                   in: content)
    }
}

/// The Organize sheet's buttons, as the design draws them.
///
/// The system's own sheet-button chrome is close but not this: the design
/// gives both a 26pt height, 6pt corners and 12pt type, fills the primary with
/// the accent and the other with a field, and shadows both a half point.
struct SheetButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: isPrimary ? .medium : .regular))
            .foregroundStyle(isPrimary ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            .padding(.horizontal, 12)
            .frame(height: Theme.Size.button)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                    .fill(isPrimary ? Theme.Colour.accent : Theme.Colour.fieldFill)
            }
            .overlay {
                if !isPrimary {
                    RoundedRectangle(cornerRadius: Theme.Radius.pill, style: .continuous)
                        .stroke(Theme.Colour.fieldBorder, lineWidth: 1)
                }
            }
            .themeShadow(Theme.Shadow.button)
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
    }
}
