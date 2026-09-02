# The interface — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ledge looks like the drawn design, in both themes, at Turkish length.

**Architecture:** One decision moves into `LedgeCore` where it can be tested — which visual family a file belongs to. Everything else is presentation: a single `Theme` file holds the scale so no view invents a number, and each surface is rebuilt against it. No filing behaviour changes.

**Tech Stack:** Swift 6, SwiftUI, Swift Testing. `LedgeCore` is a dependency-free SPM package; `Ledge` is the app target and has no tests by design.

**Spec:** `docs/superpowers/specs/2026-09-02-ledge-visual-design.md`

## Global Constraints

- Swift 6 language mode in both targets. No third-party dependencies. System frameworks (Foundation, AppKit, SwiftUI, UniformTypeIdentifiers) are fine.
- `LedgeCore` produces data; the app target produces sentences. No `String(localized:)`, `NSLocalizedString`, `LocalizedError`, `LocalizedStringResource` or `LocalizedStringKey` anywhere under `LedgeCore/Sources/` — `make strings` check 2 fails the build otherwise.
- Every user-visible string is a key in `Ledge/Resources/Localizable.xcstrings` with a `tr` value. Any `en` value present must equal its key exactly — so **omit the `en` entry** and the key itself is the English text. `make strings` check 3 enforces this.
- **Never `.textCase(.uppercase)`.** SwiftUI uppercases with the non-localised `String.uppercased()`, which turns Turkish `Son İndirilenler` into `SON İNDIRILENLER` — a dotless I in a language that distinguishes the letters. Measured twice in this project. Uppercase labels ship uppercase in the catalog.
- Never `lowercased(with: Locale.current)` or `uppercased(with:)` on matched text, for the same reason.
- Colour hierarchy is `.primary` / `.secondary` / `.tertiary` — spec §4. Do not type the rgba values from the spec's first table; they document what those system styles already produce.
- Turkish runs 27–38% longer than English. Every string added here is owed a check at Turkish length.
- No filing behaviour changes. Not what gets filed, not where, not how rules match. Spec §11.
- Never write to, delete from, or "clean up" anything under `~/Library/Application Support/Ledge/`. That is the user's real rule file and journal. Report unexpected state; do not repair it.
- Tests that touch the filesystem work in their own temporary directory. No test may touch `~/Library`.
- Every test must be demonstrated to fail against the defect it was written for. Break the line, run the test, watch it fail, restore, run again. Record both runs in the task report.
- Gate before every commit: `cd LedgeCore && swift test`, then `make build`, then `make strings`.

## New files do not reach the build on their own

`Ledge.xcodeproj` has no `PBXFileSystemSynchronizedRootGroup`; it lists every file explicitly. A new `.swift` file under `Ledge/` therefore needs four hand edits to `Ledge.xcodeproj/project.pbxproj`: a `PBXFileReference`, a `PBXBuildFile`, membership in the group its directory belongs to, and an entry in the target's Sources build phase. Copy the shape of an existing entry — `Ledge/Shelf/ShelfRow.swift` is a good model — and give each new object a fresh 24-character hex id.

`LedgeCore` is a **local Swift package** and globs its own `Sources/` directory, so a new file there needs none of this. Task 1 is the only task that adds one.

If a file is missing from the build phase the compiler will not say so; it will fail later, in whichever file first refers to the symbol that was never compiled.

## Nothing here can be seen

No agent on this project has had Screen Recording or Accessibility permission. Every task below ships unverified as *rendered*. Do not claim you checked how something looks. Report what you built and that it compiles; a human looks at it afterwards. Task 9 writes down what that human must check.

## File structure

| File | Responsibility |
|---|---|
| `LedgeCore/Sources/LedgeCore/Rules/FileKind.swift` | **new** — which visual family an extension belongs to. Pure, tested. |
| `Ledge/Design/Theme.swift` | **new** — the scale: type styles, spacing, radii, the four literal colours, the three meaning colours. The only file allowed to contain a number from the design. |
| `Ledge/Shelf/TypeBadge.swift` | **new** — the drawn 32pt page with its extension label. |
| `Ledge/Shelf/ShelfRow.swift` | the chip, the merged metadata line, the stale treatment. |
| `Ledge/Shelf/ShelfView.swift` | header chip, section labels, list, footer, empty state, the four states. |
| `Ledge/ErrorBanner.swift` | the amber banner, now with an optional action. |
| `Ledge/Onboarding/PermissionView.swift` | the permission screen's copy and treatment. |
| `Ledge/Settings/RulesPane.swift` | rubric, ordinal gutter, collapsing cards, field labels, diagnostics. |
| `Ledge/Organize/OrganizeSheet.swift` | preview grammar, caption, button. |
| `Ledge/Resources/Localizable.xcstrings` | every new and changed string, with `tr`. |
| `docs/manual-checks.md`, `docs/manual-checks.tr.md` | what a person must look at. |

---

### Task 1: Which family a file belongs to

**Files:**
- Create: `LedgeCore/Sources/LedgeCore/Rules/FileKind.swift`
- Test: `LedgeCore/Tests/LedgeCoreTests/FileKindTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `FileKind` (`.image`, `.movie`, `.document`, `.other`) and `FileKind.of(extension:) -> FileKind`.

Spec §6. The badge's colour follows the file's kind, read from its extension — not the category it was filed into. A screenshot filed into `Screenshots` still carries the image badge.

- [ ] **Step 1: Write the failing tests**

Create `LedgeCore/Tests/LedgeCoreTests/FileKindTests.swift`:

```swift
import Testing
@testable import LedgeCore

@Test func imagesAreImages() {
    #expect(FileKind.of(extension: "png") == .image)
    #expect(FileKind.of(extension: "jpg") == .image)
    #expect(FileKind.of(extension: "heic") == .image)
    #expect(FileKind.of(extension: "svg") == .image)
}

@Test func moviesAreMovies() {
    #expect(FileKind.of(extension: "mov") == .movie)
    #expect(FileKind.of(extension: "mp4") == .movie)
}

@Test func readableDocumentsAreDocuments() {
    #expect(FileKind.of(extension: "pdf") == .document)
    #expect(FileKind.of(extension: "txt") == .document)
    #expect(FileKind.of(extension: "key") == .document)
}

@Test func archivesAndAppsAndFontsAreNeitherOfThose() {
    // They conform to `public.data`, not `public.content`, which is the
    // distinction the document family rests on.
    #expect(FileKind.of(extension: "zip") == .other)
    #expect(FileKind.of(extension: "app") == .other)
    #expect(FileKind.of(extension: "ttf") == .other)
}

@Test func anExtensionMacOSHasNeverHeardOfIsOther() {
    #expect(FileKind.of(extension: "aep") == .other)
    #expect(FileKind.of(extension: "zzzznotathing") == .other)
}

@Test func noExtensionIsOther() {
    #expect(FileKind.of(extension: "") == .other)
}

@Test func theLookupFoldsCase() {
    #expect(FileKind.of(extension: "PNG") == .image)
    #expect(FileKind.of(extension: "Mov") == .movie)
}

@Test func aFormatThatIsAnImageWithoutSayingSoInItsNameIsStillAnImage() {
    // The reason this is a UTType lookup and not a list: nobody would think
    // to put `psd` in an image list, and macOS already knows.
    #expect(FileKind.of(extension: "psd") == .image)
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd LedgeCore && swift test --filter FileKindTests`
Expected: FAIL to compile — "cannot find 'FileKind' in scope".

- [ ] **Step 3: Write the lookup**

Create `LedgeCore/Sources/LedgeCore/Rules/FileKind.swift`:

```swift
import Foundation
import UniformTypeIdentifiers

/// The visual family a file belongs to, for the badge the shelf draws.
///
/// Read from the extension, never from the category the file was filed into: a
/// screenshot filed into `Screenshots` is still a PNG, and a badge that changed
/// colour depending on which rule happened to claim the file would be a rule no
/// user could predict.
///
/// Asks macOS rather than carrying a list. `psd` is an image and nobody would
/// think to write that down; a format released next year is classified
/// correctly by a system that has been taught about it, by a lookup nobody has
/// to maintain.
public enum FileKind: Sendable, Equatable {
    case image
    case movie
    case document
    case other

    /// The family for a filename extension, with or without case.
    ///
    /// Order is load-bearing. An image conforms to `public.content` as surely as
    /// a PDF does, so asking about content first would swallow every image and
    /// every video into the document family. The specific questions come first
    /// and the general one last.
    ///
    /// The document family is `public.content` — "something a person opens and
    /// reads" — and deliberately not `public.data`, which is every byte on the
    /// disk including archives, fonts and application bundles. Those get the
    /// neutral badge, which is the honest answer for things that are not
    /// documents.
    public static func of(extension ext: String) -> FileKind {
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .content) { return .document }
        return .other
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd LedgeCore && swift test`
Expected: PASS. No existing test changes.

- [ ] **Step 5: Prove each test can fail**

| Mutation | Must fail |
|---|---|
| delete the `.image` line | `imagesAreImages`, `aFormatThatIsAnImageWithoutSayingSoInItsNameIsStillAnImage` |
| delete the `.movie` line | `moviesAreMovies` |
| `conforms(to: .content)` → `conforms(to: .data)` | `archivesAndAppsAndFontsAreNeitherOfThose` |
| `ext.lowercased()` → `ext` | `theLookupFoldsCase` |
| `guard let type = … else { return .other }` → `return .document` | `anExtensionMacOSHasNeverHeardOfIsOther`, `noExtensionIsOther` |
| move the `.content` check above `.image` | `imagesAreImages`, `moviesAreMovies` |

Record the actual observed result for each row. A row that fails nothing means its test does not exist yet — write it before continuing.

- [ ] **Step 6: Commit**

```bash
git add LedgeCore/Sources/LedgeCore/Rules/FileKind.swift LedgeCore/Tests/LedgeCoreTests/FileKindTests.swift
git commit -m "feat(core): which visual family a file belongs to"
```

---

### Task 2: The scale, in one file

**Files:**
- Create: `Ledge/Design/Theme.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Theme.Space` — `panel: 12`, `card: 10`, `iconGap: 9`, `nameToMeta: 1`, `rowGap: 3`, `section: 14`
  - `Theme.Size` — `field: 22`, `button: 26`, `popup: 28`, `row: 46`, `footer: 38`, `badge: 32`
  - `Theme.Radius` — `field: 5`, `row: 7`, `card: 8`, `window: 10`, `panel: 11`
  - `Theme.Colour` — `chipFill`, `chipBorder`, `fieldFill`, `fieldBorder`, `accent`, `amber`, `amberFill`, `red`, `redFill`, `hover`, `hoverStrong`
  - `Text` modifiers: `.sectionLabel()`, `.fieldLabel()`, `.rowName()`, `.rowMeta()`, `.mono()`

Spec §2, §3, §4. This file is the only place in the app allowed to contain a number or colour from the design. A view that types `7` instead of `Theme.Radius.row` is a view that will drift.

- [ ] **Step 1: Write the file**

Create `Ledge/Design/Theme.swift`:

```swift
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

    /// 11 regular, secondary. The metadata line, captions, diagnostics.
    func rowMeta() -> some View {
        font(.system(size: 11)).foregroundStyle(.secondary)
    }

    /// 11 SF Mono, primary. Extensions, name patterns, globs.
    func mono() -> some View {
        font(.system(size: 11, design: .monospaced))
    }
}
```

- [ ] **Step 2: Register the file in the project**

`Theme.swift` is a new file under `Ledge/` and the project lists files by hand — see "New files do not reach the build on their own" above. Add its `PBXFileReference`, `PBXBuildFile`, group membership and Sources entry, modelled on an existing file.

- [ ] **Step 3: Build**

Run: `make build`, then `make strings`
Expected: build succeeds; all three string checks OK. `Theme.swift` contains no user-visible strings, so the catalog is unchanged.

Then prove the file is actually compiled — a file missing from the build phase produces no error until something references it. Add `_ = Theme.Colour.accent` temporarily inside `ShelfView.body`, build, confirm it succeeds, and remove it. Report that you did.

- [ ] **Step 4: Commit**

```bash
git add Ledge/Design/Theme.swift Ledge.xcodeproj
git commit -m "feat: the design's scale, in one file"
```

---

### Task 3: The type badge

**Files:**
- Create: `Ledge/Shelf/TypeBadge.swift`

**Interfaces:**
- Consumes: `FileKind.of(extension:)` from Task 1; `Theme` from Task 2.
- Produces: `TypeBadge(fileExtension: String)` — a 32×32 view.

Spec §6.

- [ ] **Step 1: Write the view**

Create `Ledge/Shelf/TypeBadge.swift`:

```swift
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
    /// `uppercased()` is safe here and nowhere else in this app: an extension is
    /// an ASCII token by the time it reaches this view — `RuleEditing`
    /// normalises it and `URL.pathExtension` produces it — so the Turkish `İ`
    /// case that this project has hit twice cannot arise. It is not a
    /// user-authored sentence.
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
```

- [ ] **Step 2: Register the file in the project**

`TypeBadge.swift` is a new file under `Ledge/` — add its four `project.pbxproj` entries, as Task 2 did for `Theme.swift`.

The nine badge colours it reads are already in `Theme.Colour`; Task 2 put them there. The design draws the light pages literally and the dark labels literally, and the dark page and border are derived from the dark label at 14% and 28% — the boards draw dark badges as a label on the panel's own ground rather than a filled page. That derivation is this plan's, not the design's, and belongs in the report.

- [ ] **Step 3: Build**

Run: `make build`, then `make strings`
Expected: both clean.

- [ ] **Step 4: Commit**

```bash
git add Ledge/Shelf/TypeBadge.swift Ledge.xcodeproj
git commit -m "feat: the drawn type badge"
```

---
### Task 4: The shelf row

**Files:**
- Modify: `Ledge/Shelf/ShelfRow.swift`

**Interfaces:**
- Consumes: `TypeBadge(fileExtension:)` from Task 3; `Theme` from Task 2.
- Produces: no API. `ShelfRow(record:isPresent:icon:onUndo:)` keeps its signature for now; Task 5 removes the `icon` parameter once nothing passes it.

Spec §1, §5. This is the task the whole design turns on: **a row is a contained chip, not a log line.** Containment is the drag affordance.

- [ ] **Step 1: Replace the row's body and its two computed helpers**

In `Ledge/Shelf/ShelfRow.swift`, keep everything above `var body` — the doc comments, `isStillThere()`, `destinationTrail`, `filedWhen`, `relative` — unchanged. They carry findings that were measured and are not this task's business.

Replace `var body` and the `fileIcon` property with:

```swift
    var body: some View {
        HStack(spacing: Theme.Space.iconGap) {
            TypeBadge(fileExtension: record.to.pathExtension)
                .opacity(isPresent ? 1 : 0.35)
                .grayscale(isPresent ? 0 : 1)

            VStack(alignment: .leading, spacing: Theme.Space.nameToMeta) {
                Text(record.originalName)
                    .rowName()
                    .foregroundStyle(isPresent ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                // Destination, subdivision and time are peers in one line that
                // truncates from the tail, so time degrades first — it is the
                // least load-bearing of the three. The rejected alternative gave
                // time its own right-aligned slot, which put three claims on one
                // edge and lost the argument to Turkish.
                Text(metadata)
                    .font(.system(size: 11))
                    .foregroundStyle(isPresent ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
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
            .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
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
        .shadow(color: .black.opacity(isPresent ? 0.06 : 0), radius: 1, y: 1)
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
        isPresent
            ? "\(destinationTrail) · \(filedWhen)"
            : "\(String(localized: "Moved or deleted")) · \(filedWhen)"
    }
```

- [ ] **Step 1a: Name the project in a row filed under one**

Spec §5: a row filed under a project shows the project name where the
destination would be. `destinationTrail` cannot produce it — under a project
the destination is not below `record.from`, so it falls back to the
destination folder's last component, which is the *category* (`Documents`),
not the project.

`MoveRecord` does not carry the project, so the row cannot know it on its own.
Pass it in: add to `ShelfRow`

```swift
    /// The project this row was filed under, when it was filed under one.
    /// Nil for everything filed into a watched folder.
    let projectName: String?
```

and use it in `metadata`:

```swift
    private var metadata: String {
        guard isPresent else {
            return "\(String(localized: "Moved or deleted")) · \(filedWhen)"
        }
        return "\(projectName ?? destinationTrail) · \(filedWhen)"
    }
```

A stored `let` cannot carry a default a caller may override, so adding it
breaks `ShelfView`'s call site and with it this task's own build gate. Pass a
literal there for now — in `ShelfView.swift`, inside the `ShelfRow(...)` call:

```swift
                                projectName: nil,
```

Task 5 replaces that literal with the real lookup, which matches `record.to`
against each known project's folder: a project owns a folder, and a record
filed under one has a destination inside it. Leaving it `nil` for one commit
costs a row its project name until Task 5 lands, and keeps every revision on
the branch building.

- [ ] **Step 2: Delete the now-unused icon parameter's use**

`ShelfRow` still declares `let icon: NSImage?`. Leave the declaration — Task 5 removes it along with the sweep that computes it, and removing it here would break `ShelfView` mid-task. Delete only the `fileIcon` view it fed.

- [ ] **Step 3: Build**

Run: `make build`, then `make strings`, then `cd LedgeCore && swift test`
Expected: all three clean. `Moved or deleted` and `Undo this move` are already in the catalog; no new keys.

- [ ] **Step 4: Commit**

```bash
git add Ledge/Shelf/ShelfRow.swift
git commit -m "feat: the shelf row as a chip, with one metadata line"
```

---

### Task 5: The shelf's chrome

**Files:**
- Modify: `Ledge/Shelf/ShelfView.swift`
- Modify: `Ledge/Shelf/ShelfRow.swift` — remove `icon`

**Interfaces:**
- Consumes: `Theme` from Task 2; `ShelfRow` from Task 4.
- Produces: `ShelfRow(record:isPresent:onUndo:)` — the `icon` parameter is gone.

Spec §5. The header chip, the section labels, the list, the footer, and the empty state.

- [ ] **Step 1: Remove the icon sweep**

`ShelfRow` now draws its own badge from the record's extension, so the per-row `NSImage` the shelf was fetching is dead weight — a filesystem read per visible row, on every sweep, for a picture nothing draws.

In `Ledge/Shelf/ShelfRow.swift`, delete the `let icon: NSImage?` declaration and its doc comment.

In `Ledge/Shelf/ShelfView.swift`: delete `icon` from the `ShelfRow(...)` call site; remove the `icon` field from the `RowStatus` type and stop computing it in `refreshRowStatus()`. Keep `isPresent` and the whole generation guard — that sweep is still what tells a live row from a stale one, and its `rowStatusGeneration` comment records a race it exists to prevent.

- [ ] **Step 2: Rebuild the destination header**

Replace `destinationHeader` with:

```swift
    /// Names where downloads are going right now, and lets the user change it.
    /// Without this, project mode is invisible: nothing else in the shelf says
    /// which folder the next download will land in.
    private var destinationHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("FILING INTO")
                .sectionLabel()

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
                HStack(spacing: 7) {
                    Text(state.activeProject?.name ?? defaultDestinationName)
                        .rowName()
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
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
                .frame(height: Theme.Size.popup)
                .background {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.Colour.chipFill)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Theme.Colour.chipBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.08), radius: 0.75, y: 0.5)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
        }
        .padding(.horizontal, Theme.Space.panel)
        .padding(.top, Theme.Space.panel)
    }
```

- [ ] **Step 3: Rebuild the list and the empty state**

In `shelf`, replace the `Text("RECENT DOWNLOADS")` block, the empty-state branch and the `LazyVStack` spacing with:

```swift
            Text("RECENT DOWNLOADS")
                .sectionLabel()
                .padding(.horizontal, Theme.Space.panel)
                .padding(.top, Theme.Space.section)
                .padding(.bottom, 5)

            if state.recentRecords.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Nothing filed yet")
                        .font(.system(size: 13, weight: .semibold))
                    // The only line in the app that explains the product.
                    Text("New downloads appear here — drag any row to use the file.")
                        .rowMeta()
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.panel)
                .padding(.vertical, 22)
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.Space.rowGap) {
                        ForEach(state.recentRecords) { record in
                            // Until the first sweep lands, a row shows as
                            // present: the display is briefly optimistic, while
                            // the row's own gesture-time check keeps what it
                            // *does* correct either way.
                            ShelfRow(
                                record: record,
                                isPresent: rowStatus[record.id]?.isPresent ?? true,
                                projectName: projectName(for: record)
                            ) {
                                Task { await state.undo(record) }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
                .frame(maxHeight: 340)
            }
```

Delete the `Divider()` that used to sit between the header and the list — the design separates those two by space, not a rule.

Add to `ShelfView`:

```swift
    /// The project a record was filed under, or nil.
    ///
    /// Matched by containment rather than stored on the record, because
    /// `MoveRecord` deliberately records where a file was *found* — that is
    /// what undo needs — and a project changes only where it went.
    private func projectName(for record: MoveRecord) -> String? {
        state.projects.first { project in
            record.to.path.hasPrefix(project.folder.path + "/")
        }?.name
    }
```

- [ ] **Step 4: Rebuild the footer**

Replace `footer` with:

```swift
    /// Organize, Settings and Quit. Rendered outside `shelf` so that no state —
    /// including one where Ledge cannot read a thing — can take them away.
    private var footer: some View {
        HStack(spacing: 0) {
            Button("Organize Now…") { showingOrganize = true }
                .buttonStyle(.plain)
                .rowName()
                .foregroundStyle(Theme.Colour.accent)
                // Only when there is nowhere left to organize *from*.
                .disabled(!state.hasUsableFolder)

            Spacer()

            SettingsLink {
                Image(systemName: "gearshape")
                    .frame(width: 28, height: Theme.Size.button)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "Settings"))

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .frame(width: 28, height: Theme.Size.button)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(String(localized: "Quit Ledge"))
        }
        .padding(.leading, Theme.Space.panel)
        .padding(.trailing, 6)
        .frame(height: Theme.Size.footer)
    }
```

- [ ] **Step 5: Give the panel its ground and radius**

On the outermost `VStack` in `body`, replace `.frame(width: 360)` with:

```swift
        .frame(width: 360)
        // The boards specify a translucent fill and a 36pt blur, which is how
        // the web imitates macOS vibrancy. A material is the real thing: it
        // behaves correctly over any wallpaper and in both themes, which a
        // fixed rgba cannot. Spec §8.2.
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
```

- [ ] **Step 6: Add the two new strings**

Add to `Ledge/Resources/Localizable.xcstrings`, each with a `tr` value and **no `en` entry**:

| Key | `tr` |
|---|---|
| `Nothing filed yet` | `Henüz klasörlenen bir şey yok` |
| `New downloads appear here — drag any row to use the file.` | `Yeni indirilenler burada görünür — dosyayı kullanmak için satırı sürükleyin.` |

Remove the now-unused key `Nothing filed yet.` (with the full stop) if nothing else references it.

- [ ] **Step 7: Build**

Run: `make build`, then `make strings`, then `cd LedgeCore && swift test`
Expected: all three clean.

- [ ] **Step 8: Commit**

```bash
git add Ledge/Shelf/ShelfView.swift Ledge/Shelf/ShelfRow.swift Ledge/Resources/Localizable.xcstrings
git commit -m "feat: the shelf's header, list and footer"
```

---

### Task 6: The shelf's four states

**Files:**
- Modify: `Ledge/ErrorBanner.swift`
- Modify: `Ledge/Shelf/ShelfView.swift`
- Modify: `Ledge/Onboarding/PermissionView.swift`

**Interfaces:**
- Consumes: `Theme` from Task 2.
- Produces: `ErrorBanner(message:actionTitle:onAction:onDismiss:)` — the Privacy-Settings-specific parameter becomes a general one.

Spec §5's state list. Empty is Task 5's; these are the other three plus the banner.

- [ ] **Step 1: Generalise the banner**

`ErrorBanner` currently takes `onOpenPrivacySettings: (() -> Void)?`. The design gives the unavailable-folder banner its own action (`Klasörü Yeniden Seç…`), so the parameter becomes a title and a closure. Replace the properties and body:

```swift
struct ErrorBanner: View {
    let message: String?
    let horizontalPadding: CGFloat
    let topPadding: CGFloat
    /// Non-nil only when there is a route out of this failure — see
    /// `AppState.isPermissionDenied` for the one that offers Privacy Settings.
    ///
    /// Declared before `onDismiss` on purpose: the trailing closure at every
    /// call site binds to the last parameter, and this one is not a literal.
    var action: (title: String, run: () -> Void)?
    let onDismiss: () -> Void

    var body: some View {
        if let message {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.Colour.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.Colour.amber)
                        .fixedSize(horizontal: false, vertical: true)
                    if let action {
                        Button(action.title, action: action.run)
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.Colour.amber)
                            .underline()
                    }
                }
                Spacer(minLength: 4)
                Button(action: onDismiss) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Colour.amber.opacity(0.7))
                .help(String(localized: "Dismiss"))
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colour.amberFill)
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, topPadding)
        }
    }
}
```

Update the three call sites — `ShelfView.errorBanner`, `OrganizeSheet`, `SettingsView` — replacing

```swift
                    onOpenPrivacySettings: state.lastErrorOffersPrivacySettings
                        ? { PrivacySettings.open() } : nil) {
```

with

```swift
                    action: state.lastErrorOffersPrivacySettings
                        ? (String(localized: "Open Privacy Settings"), { PrivacySettings.open() })
                        : nil) {
```

- [ ] **Step 2: Give the unavailable-folder banner its action**

Find `unavailableFolderBanner` in `ShelfView.swift`. Give it the same treatment as `errorBanner` — the amber pill above — and an action that opens the watched-folders list so the user can re-pick:

```swift
                action: (String(localized: "Choose Folder Again…"), {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    SettingsLauncher.openWatchedFolders()
                })
```

Add the launcher to `ShelfView.swift` — there is none today, and `SettingsLink` is a view, so it cannot be called from a closure:

```swift
/// Opens Settings on the pane holding the watched-folder list.
///
/// The banner needs a route out and `SettingsLink` cannot be used from a
/// closure, so this is the AppKit equivalent of the footer's gear.
enum SettingsLauncher {
    static func openWatchedFolders() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
```

- [ ] **Step 3: Restyle the permission screen**

In `Ledge/Onboarding/PermissionView.swift`, keep every doc comment and keep `folderName` exactly as it is — the reasoning about localized names in a translated sentence is measured and correct, and the board's literal "Downloads" is just the common case that interpolation already produces.

Replace the body's first two children:

```swift
            Text("Ledge can't see your \(folderName) folder")
                .font(.system(size: 13, weight: .semibold))

            Text("Grant access under Privacy & Security → Files and Folders, then Ledge resumes automatically.")
                .rowMeta()
                .fixedSize(horizontal: false, vertical: true)
```

and the button:

```swift
            Button("Open System Settings…", action: openPrivacySettings)
                .buttonStyle(.plain)
                .rowName()
                .foregroundStyle(Theme.Colour.accent)
```

Change the outer padding from `.padding(16)` to `.padding(Theme.Space.panel)`.

- [ ] **Step 4: Tint the header in project mode**

In `destinationHeader`, when `state.activeProject != nil`, the design tints the header and adds a caption and an End button. After the `Menu`, add:

```swift
            if let project = state.activeProject {
                Text("All new downloads go here until you end the project.")
                    .rowMeta()
                    .fixedSize(horizontal: false, vertical: true)
                Button("End") { state.setActiveProject(nil) }
                    .buttonStyle(.plain)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Colour.accent)
                    .accessibilityLabel(Text("End project \(project.name)"))
            }
```

and give the whole header a tint when a project is active by adding, after its two `.padding` modifiers:

```swift
        .padding(.bottom, state.activeProject == nil ? 0 : 10)
        .background(state.activeProject == nil ? Color.clear : Theme.Colour.accent.opacity(0.08))
```

- [ ] **Step 5: Add the new strings**

| Key | `tr` |
|---|---|
| `Choose Folder Again…` | `Klasörü Yeniden Seç…` |
| `Ledge can't see your %@ folder` | `Ledge, %@ klasörünü göremiyor` |
| `Grant access under Privacy & Security → Files and Folders, then Ledge resumes automatically.` | `Gizlilik ve Güvenlik → Dosyalar ve Klasörler altından erişim verin, Ledge kendiliğinden devam eder.` |
| `Open System Settings…` | `Sistem Ayarlarını Aç…` |
| `All new downloads go here until you end the project.` | `Projeyi bitirene kadar yeni indirilenler buraya gider.` |
| `End` | `Bitir` |
| `End project %@` | `%@ projesini bitir` |

Remove the keys that are no longer referenced: the old permission headline and explanation, and `Open Privacy Settings` **only if** Task 6 Step 1 left no call site using it — it is still used by the error banner's action, so expect it to stay.

- [ ] **Step 6: Build**

Run: `make build`, then `make strings`, then `cd LedgeCore && swift test`
Expected: all three clean. Check 1 will name any key you removed that is still referenced, and any you added that is missing a `tr`.

- [ ] **Step 7: Commit**

```bash
git add Ledge/ErrorBanner.swift Ledge/Shelf/ShelfView.swift Ledge/Onboarding/PermissionView.swift Ledge/Organize/OrganizeSheet.swift Ledge/Settings/SettingsView.swift Ledge/Resources/Localizable.xcstrings
git commit -m "feat: the shelf's warning, permission and project states"
```

---
### Task 7: The Rules tab

**Files:**
- Modify: `Ledge/Settings/RulesPane.swift`

**Interfaces:**
- Consumes: `Theme` from Task 2.
- Produces: no API.

Spec §7. The densest surface in the app, and the one the design most changes.

**One thing deliberately not built.** The boards draw a drag grip under the ordinal and describe precedence as carried three ways. This task builds two of them — the ordinal and the rubric — and keeps the existing up/down buttons, restyled. Drag-to-reorder is its own piece of work with its own drop-target and accessibility questions, and the buttons already do the job from the keyboard. Removing them for a grip would repeat the mistake the design itself avoided with hover-only undo. Say so in the report; it is a knowing omission, not a miss.

- [ ] **Step 1: Replace the rubric**

The pane currently renders the key `Categories are matched top to bottom. The first one that claims a file wins.` The boards word it differently and the boards win (spec §8.5). Replace that `Text` with:

```swift
            Text("Rules apply top to bottom — the first rule that claims a file wins.")
                .rowMeta()
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.panel)
                .padding(.bottom, 8)
```

- [ ] **Step 2: Give the card its gutter and its ordinal**

In the category row view's `body`, wrap the existing content in an `HStack` whose first child is the gutter. Replace the outermost `HStack(alignment: .top, spacing: 8) {` with:

```swift
        HStack(alignment: .top, spacing: Theme.Space.card) {
            VStack(spacing: 6) {
                Text("\(position.index + 1)")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()

                Button { move(-1) } label: {
                    Image(systemName: "chevron.up").font(.system(size: 9, weight: .bold))
                }
                .disabled(!position.canMoveUp)
                .help("Move up — earlier rules win ties")

                Button { move(1) } label: {
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
                }
                .disabled(!position.canMoveDown)
                .help("Move down — later rules only see what's left")
            }
            .buttonStyle(ArrowButtonStyle())
            .frame(width: 20)
            .padding(.top, 2)
```

and delete the trailing `VStack(spacing: 2) { … }` that held the up/down/remove buttons on the right, moving its remove button to the card's own trailing edge:

```swift
            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle").font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Remove this category")
```

`RowPosition` (`RulesPane.swift:289`) carries only `canMoveUp` and `canMoveDown`; the ordinal cannot be derived from those. Add the field:

```swift
private struct RowPosition: Equatable {
    /// Zero-based, so the gutter can show `index + 1`. Precedence is the whole
    /// point of this pane and the number is how the user reads it.
    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
}
```

and pass it at both construction sites (`RulesPane.swift:186` and `:188`) — the disabled one takes the row's own index too, not a placeholder.

Add the arrow style at the bottom of the file:

```swift
/// The 20×18 reorder buttons in a rule card's gutter.
private struct ArrowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 20, height: 18)
            .background {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(white: 0.5, opacity: configuration.isPressed ? 0.22 : 0.12))
            }
            .foregroundStyle(.secondary)
    }
}
```

- [ ] **Step 3: Make the card a card, and collapse it when clean**

Wrap the card's content column in the chip treatment and hide the fields when there is nothing to say:

```swift
            VStack(alignment: .leading, spacing: 6) {
                TextField("Name", text: $category.name)
                    .textFieldStyle(.plain)
                    .rowName()
                    .fontWeight(.medium)

                if isExpanded {
                    fieldsAndDiagnostics
                } else {
                    Text(collapsedSummary)
                        .mono()
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
```

with, as computed properties on the row view:

```swift
    /// A clean rule with nothing to say collapses to its name and its
    /// extensions. It expands the moment it has patterns to show or a
    /// diagnostic to raise — the two cases where the fields are the point.
    private var isExpanded: Bool {
        isEditing || !category.namePatterns.isEmpty || !messages.isEmpty
    }

    /// What a collapsed card shows in place of its fields.
    private var collapsedSummary: String {
        category.extensions.isEmpty
            ? String(localized: "no extensions")
            : category.extensions.joined(separator: " ")
    }
```

`isEditing` is `isEditingExtensions || isEditingPatterns` — both `@FocusState` values already exist on this view. A card being typed into must never collapse under the cursor.

Wrap the whole `HStack` in the card treatment:

```swift
        .padding(.vertical, 9)
        .padding(.horizontal, Theme.Space.card)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colour.chipFill)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .stroke(Theme.Colour.chipBorder, lineWidth: 1)
        }
```

- [ ] **Step 4: Restyle the fields, their labels and the segmented control**

The extensions field and the patterns editor take the design's field treatment. Give each a `fieldLabel()` caption above it:

```swift
                    Text("EXTENSIONS")
                        .fieldLabel()
                    TextField("", text: $typedExtensions)
                        .textFieldStyle(.plain)
                        .mono()
                        .padding(.horizontal, 6)
                        .frame(height: Theme.Size.field)
                        .background {
                            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                                .fill(Theme.Colour.fieldFill)
                        }
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.field, style: .continuous)
                                .stroke(Theme.Colour.fieldBorder, lineWidth: 1)
                        }
                        .focused($isEditingExtensions)
                        .onSubmit(tidy)
```

The patterns editor keeps its `TextEditor` and its `FocusState` — the comment explaining why it cannot be a `TextField` stays — and takes the same fill, border and radius, with the label `NAME PATTERNS · ONE PER LINE` replacing the current sentence-case caption.

The subdivision picker keeps `.pickerStyle(.segmented)` and `.labelsHidden()`; the design's segmented control is the system one.

- [ ] **Step 5: Restyle the diagnostics**

Replace `MessageList`'s row rendering so a warning is an amber pill and a blocking problem a red one:

```swift
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: message.isBlocking ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                Text(message.text)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .foregroundStyle(message.isBlocking ? Theme.Colour.red : Theme.Colour.amber)
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(message.isBlocking ? Theme.Colour.redFill : Theme.Colour.amberFill)
            }
            .padding(.top, 7)
```

The Turkish two-sentence diagnostic wraps to two lines and the card grows; the list scrolls inside the fixed window, so nothing is clipped. `.fixedSize(horizontal: false, vertical: true)` is what guarantees it — do not remove it to make a screenshot tidier.

- [ ] **Step 6: Name where unclaimed files go**

Below the list, beside `＋ Add Rule`, the boards say `Everything else stays in Downloads`. That is not what Ledge does (spec §8.1). Render the truth instead, naming the fallback the user actually has:

```swift
            Text("Everything else goes to \(draft.fallbackName)")
                .rowMeta()
```

- [ ] **Step 7: Add the new strings**

| Key | `tr` |
|---|---|
| `Rules apply top to bottom — the first rule that claims a file wins.` | `Kurallar yukarıdan aşağıya uygulanır — dosyayı ilk sahiplenen kural kazanır.` |
| `EXTENSIONS` | `UZANTILAR` |
| `NAME PATTERNS · ONE PER LINE` | `AD DESENLERİ · SATIR BAŞINA BİR TANE` |
| `no extensions` | `uzantı yok` |
| `Everything else goes to %@` | `Geri kalan her şey %@ klasörüne gider` |

Remove `Categories are matched top to bottom. The first one that claims a file wins.` and `Name patterns — one per line, * matches anything`, both now unreferenced.

The two uppercase keys ship uppercase in the catalog, per the global constraint. `AD DESENLERİ` carries a dotted `İ`; that is why it is written here and not produced by `.textCase`.

- [ ] **Step 8: Build**

Run: `make build`, then `make strings`, then `cd LedgeCore && swift test`
Expected: all three clean.

- [ ] **Step 9: Commit**

```bash
git add Ledge/Settings/RulesPane.swift Ledge/Resources/Localizable.xcstrings
git commit -m "feat: the Rules tab as cards with an ordinal gutter"
```

---

### Task 8: Organize Now

**Files:**
- Modify: `Ledge/Organize/OrganizeSheet.swift`

**Interfaces:**
- Consumes: `Theme` from Task 2.
- Produces: no API.

Spec §7's second half.

- [ ] **Step 1: Rebuild the header**

Replace the three caption lines with the boards' single one, keeping the folder picker below it:

```swift
            Text("Organize Now")
                .font(.system(size: 13, weight: .semibold))

            Text("\(preview.plan.count) items would move. Folders move whole — Ledge never files their contents.")
                .rowMeta()
                .fixedSize(horizontal: false, vertical: true)
```

The sentence about names never being overwritten leaves the header; it is a reassurance the preview itself now demonstrates, and the boards give the header one line.

- [ ] **Step 2: Give preview rows the shelf's grammar**

Each row is the name on the left and the destination on the right, so a reader's eye runs down one column for *what* and another for *where*:

```swift
                HStack(spacing: 8) {
                    Text(item.source.lastPathComponent)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 12)
                    Text(destinationLabel(for: item))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
```

with:

```swift
    /// Where one planned move lands, said the way the shelf says it.
    ///
    /// A folder is named as a whole rather than given a destination trail,
    /// because Ledge never looks inside one and a trail would imply it had.
    private func destinationLabel(for item: PlannedMove) -> String {
        item.isFolder
            ? String(localized: "\(item.destination.category) · whole folder")
            : item.destination.folder.lastPathComponent
    }
```

`PlannedMove` does not carry that fact yet. Step 2a adds it — from data `ScanEngine` already has, so no filesystem read moves onto the main actor.

- [ ] **Step 2a: Let a planned move say whether it is a folder**

`ScanEngine.plan` already builds a `FileFacts` per entry and throws it away. The label above needs one bit of it.

In `LedgeCore/Sources/LedgeCore/Organize/ScanEngine.swift`, add to `PlannedMove`:

```swift
    /// Whether this entry is filed as one opaque unit rather than by its
    /// extension — a browsable folder.
    ///
    /// A package (`.app`, `.sketch`) is moved whole too, but it is not a
    /// *folder* to anyone reading the preview: it has an extension, a rule
    /// claims it by that extension, and calling it a folder would say the
    /// opposite of what happened to it.
    public let isFolder: Bool
```

with `isFolder: Bool = false` in the memberwise initializer, and at the call site inside `plan`:

```swift
                return PlannedMove(source: url,
                                   destination: destination,
                                   isFolder: facts.isDirectory && !facts.isPackage)
```

Add to `LedgeCore/Tests/LedgeCoreTests/ScanEngineTests.swift`:

```swift
@Test func aPlanMarksBrowsableFoldersAndNotPackages() throws {
    let dir = try TempDirectory()
    try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("Project"),
                                            withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: dir.url.appendingPathComponent("Thing.app"),
                                            withIntermediateDirectories: true)
    try Data().write(to: dir.url.appendingPathComponent("a.png"))

    let plan = ScanEngine.plan(folder: dir.url, using: .defaults)
    func entry(_ name: String) -> PlannedMove? { plan.first { $0.source.lastPathComponent == name } }

    #expect(entry("Project")?.isFolder == true)
    #expect(entry("Thing.app")?.isFolder == false)
    #expect(entry("a.png")?.isFolder == false)
}
```

Run it, then mutate `facts.isDirectory && !facts.isPackage` to `facts.isDirectory` and confirm the `Thing.app` expectation fails; restore and re-run. Record both.

- [ ] **Step 3: Rebuild the footer**

```swift
            Text("One undo restores the whole batch")
                .rowMeta()
            Spacer()
            Button("Cancel") { dismiss() }
            Button("Move \(movableCount) Items") { … }
                .keyboardShortcut(.defaultAction)
                .disabled(movableCount == 0 || isMoving)
```

`movableCount` is `preview.plan.count` minus `excluded.count` — every planned move, including the ones landing in the fallback. The boards count unclaimed files out of the button because they leave them in place; Ledge moves them, so it counts them (spec §8.1).

- [ ] **Step 4: Add the new strings**

| Key | `tr` |
|---|---|
| `%lld items would move. Folders move whole — Ledge never files their contents.` | `%lld öğe taşınacak. Klasörler bütün halinde taşınır — Ledge içlerini klasörlemez.` |
| `%@ · whole folder` | `%@ · klasörün tamamı` |
| `One undo restores the whole batch` | `Tek geri alma tüm grubu geri getirir` |
| `Move %lld Items` | `%lld Öğeyi Taşı` |

`Move %lld` already exists with the `tr` value `%lld Öğeyi Taşı`; if the format string changes, move the translation across and remove the old key rather than leaving both.

Remove `Nothing is overwritten. A name already in use gets a number.` if Step 1 left it unreferenced.

- [ ] **Step 5: Build**

Run: `make build`, then `make strings`, then `cd LedgeCore && swift test`
Expected: all three clean.

- [ ] **Step 6: Commit**

```bash
git add Ledge/Organize/OrganizeSheet.swift Ledge/Resources/Localizable.xcstrings
git commit -m "feat: Organize Now in the design's grammar"
```

---

### Task 9: What a person has to look at

**Files:**
- Modify: `docs/manual-checks.md`
- Modify: `docs/manual-checks.tr.md`
- Modify: `docs/known-limitations.md`

**Interfaces:** none.

Spec §10. Everything above ships unseen. This task writes down what that costs and who pays it.

- [ ] **Step 1: Add a visual pass to both check lists**

Both files are the same list in two languages; a change to one is owed to the other. Add a new section before the closing "what could not be established" section, and renumber:

> **The visual pass.** Look at the shelf in light and in dark, then again with
> Ledge set to Turkish (System Settings → General → Language & Region → the
> per-app list). In each of the four combinations:
>
> - A filed row reads as an object you could pick up, not a line in a log.
>   That containment is the whole design; if the rows read as a list, say so.
> - A stale row is flat and obviously dead, and its undo is still *visible* —
>   dimmed, not gone.
> - The metadata line truncates from the right, so the destination survives and
>   the time is what disappears. `Taşınmış veya silinmiş · 26 dk önce` must fit.
> - Tab to the undo button. It takes a focus ring and fires on Return. If it
>   cannot be reached without a pointer, that is a defect and not a nitpick.
> - Settings → Rules: put two rules into a warning state at once and give one a
>   Turkish diagnostic. The card grows, the list scrolls, nothing is clipped.
> - The type badge on a screenshot is the image colour, not the Screenshots
>   category's — a PNG looks like an image wherever it lands.

- [ ] **Step 2: Say plainly that the existing checks still bind**

Add to both files, in the visual section:

> None of this replaces the checks above. An interface that looks better and
> breaks the drag-out, undo, the stale row, project routing, the
> folder-as-one-unit rule or the eject lockout is a loss, not a trade.

- [ ] **Step 3: Record the two knowing omissions**

Append to `docs/known-limitations.md`:

> ## The Rules tab has no drag-to-reorder
>
> The design carries precedence three ways: an ordinal, a drag grip, and the
> rubric. Two shipped. Reordering is by the up/down buttons, which work from
> the keyboard; the grip was left for a piece of work that can give drop
> targets and accessibility the attention they need. Nothing is missing — this
> is a second route that does not exist yet.
>
> ## The accent colour is pinned
>
> `#0a6cd6` light, `#409cff` dark, rather than `Color.accentColor`. A user who
> has set a pink system accent sees the design's blue. That followed from the
> instruction that it look exactly like the design, and it is recorded here so
> the next person reads it as a decision rather than an oversight.

- [ ] **Step 4: Verify the two lists still match**

Run:

```bash
grep -c "^## " docs/manual-checks.md docs/manual-checks.tr.md
```

Expected: the same count from both. If they differ, one file gained a section the other did not.

- [ ] **Step 5: Commit**

```bash
git add docs/manual-checks.md docs/manual-checks.tr.md docs/known-limitations.md
git commit -m "docs: what a person has to look at, and what shipped unbuilt"
```

---

## After the last task

Run the whole gate once more: `cd LedgeCore && swift test`, `make build`, `make strings`.

Then launch the app and leave it running. Every task in this plan produced something nobody has seen; the first person to look at it is the reviewer of this branch, and they need it on screen rather than in a diff.
