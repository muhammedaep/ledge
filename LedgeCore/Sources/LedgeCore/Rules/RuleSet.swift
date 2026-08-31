import Foundation

/// An ordered list of categories. The first category claiming an extension wins,
/// which is what makes the order user-editable and meaningful.
public struct RuleSet: Codable, Equatable, Sendable {
    public var categories: [Category]
    public var fallbackName: String

    public init(categories: [Category], fallbackName: String = "Other") {
        self.categories = categories
        self.fallbackName = fallbackName
    }

    public static let defaults = RuleSet(categories: [
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
    ])
}
