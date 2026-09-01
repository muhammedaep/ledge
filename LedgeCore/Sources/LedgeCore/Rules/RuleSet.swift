import Foundation

/// An ordered list of categories. The first category claiming an extension wins,
/// which is what makes the order user-editable and meaningful.
public struct RuleSet: Codable, Equatable, Sendable {
    public var categories: [Category]
    public var fallbackName: String

    /// Which one-time edits Ledge has already made to this rule set, by name.
    ///
    /// Kept sorted so the saved file is byte-stable across runs.
    ///
    /// This is what separates a migration from a policy. Adding `Screenshots`
    /// to `defaults` reaches only new installs; running the insert on every
    /// launch would put back a rule the user deliberately deleted. The marker
    /// says "this was offered once", which is the whole of the promise.
    public var appliedMigrations: [String]

    public init(
        categories: [Category],
        fallbackName: String = "Other",
        appliedMigrations: [String] = []
    ) {
        self.categories = categories
        self.fallbackName = fallbackName
        self.appliedMigrations = appliedMigrations.sorted()
    }

    /// Hand-written for the same reason as `Category`'s: every `rules.json`
    /// already on disk is missing this key, and the synthesised decoder would
    /// reject all of them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([Category].self, forKey: .categories)
        fallbackName = try container.decode(String.self, forKey: .fallbackName)
        appliedMigrations =
            (try container.decodeIfPresent([String].self, forKey: .appliedMigrations) ?? []).sorted()
    }

    /// The top-level folder names this rule set files *into*.
    ///
    /// An entry with one of these names is a destination, not a download, and
    /// must never be filed itself. Both filing paths need this and for the same
    /// reason: the live watcher sees the destination folder appear the moment
    /// the first automatic move creates it, and would otherwise file `Documents`
    /// into `Other/Documents` on the very next event — relocating everything
    /// already filed there. Organize Now hits the same case on a folder that has
    /// been organized before.
    ///
    /// Only top-level names are listed. Subdivision folders (`Images/PNG`,
    /// `Images/2026-08`) sit inside a category folder, and both filing paths
    /// read a folder at depth 1, so neither ever sees them as candidates.
    public var destinationFolderNames: Set<String> {
        Set(categories.map(\.name)).union([fallbackName])
    }

    public static let screenshotsMigration = "screenshots-category"

    /// The rule that gives screen captures their own folder.
    ///
    /// Patterns only, because a screenshot is a `.png` like any other and the
    /// extension is exactly what fails to distinguish it.
    ///
    /// Three prefixes, each seen rather than guessed: `CleanShot ` is what
    /// CleanShot X writes, `Screenshot ` is macOS's current English name and
    /// `Screen Shot ` its older one. Localised macOS names are not covered —
    /// this list will not guess at a string nobody has looked at — and the
    /// editor is where a user adds their own.
    ///
    /// Screen *recordings* from the same tools carry the same prefix and land
    /// here too. That is intended: they are screen captures.
    public static let screenshotsCategory = Category(
        name: "Screenshots",
        extensions: [],
        namePatterns: ["CleanShot *", "Screenshot *", "Screen Shot *"]
    )

    /// This rule set with every one-time edit applied that it has not seen.
    ///
    /// Pure, so the decision is testable and the writing is the caller's.
    ///
    /// `Screenshots` goes immediately above the first category claiming `png`,
    /// stated as a position relative to its competitor rather than a fixed
    /// index so it stays correct against a rule set the user has reordered.
    /// Below that category it would never fire, because first match wins.
    public func migrated() -> RuleSet {
        guard !appliedMigrations.contains(Self.screenshotsMigration) else { return self }

        var result = self
        result.appliedMigrations = (appliedMigrations + [Self.screenshotsMigration]).sorted()

        // A category the user already calls Screenshots is theirs. Compared by
        // `folderNameKey`, which is how the rest of the app decides two names
        // are the same folder on a case-insensitive disk.
        let wanted = Category.folderNameKey(Self.screenshotsCategory.name)
        guard !categories.contains(where: { Category.folderNameKey($0.name) == wanted })
        else { return result }

        let index = categories.firstIndex { $0.extensions.contains("png") } ?? 0
        result.categories.insert(Self.screenshotsCategory, at: index)
        return result
    }

    public static let defaults = RuleSet(categories: [
        screenshotsCategory,
        Category(name: "Images",
                 extensions: ["png", "jpg", "jpeg", "gif", "svg", "webp", "heic", "avif", "tiff", "bmp", "dng"],
                 subdivision: .byExtension),
        Category(name: "Videos",
                 extensions: ["mp4", "mov", "webm", "avi", "mkv", "m4v", "mpg", "mpeg"]),
        Category(name: "Audio",
                 extensions: ["mp3", "wav", "m4a", "flac", "aac", "aiff", "ogg"]),
        Category(name: "Documents",
                 extensions: ["pdf", "docx", "doc", "xlsx", "xls", "pptx", "ppt",
                              "csv", "txt", "md", "rtf", "epub", "pages", "numbers", "key"]),
        Category(name: "Archives",
                 extensions: ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmgpart"]),
        Category(name: "Apps",
                 extensions: ["dmg", "pkg", "app", "mpkg"]),
        Category(name: "Design",
                 extensions: ["psd", "ai", "aep", "aet", "prproj", "sketch", "fig",
                              "mogrt", "indd", "xd", "afdesign", "afphoto"]),
        Category(name: "Fonts",
                 extensions: ["ttf", "otf", "woff", "woff2", "ttc", "eot"]),
        Category(name: "Code",
                 extensions: ["json", "js", "ts", "py", "sh", "html", "css", "xml",
                              "yaml", "yml", "swift", "rb", "go", "rs", "jsx", "jsxbin"])
    ], appliedMigrations: [screenshotsMigration])
}
