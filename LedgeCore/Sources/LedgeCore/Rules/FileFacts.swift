import Foundation

/// An inert description of a file, so categorization never has to touch the disk.
public struct FileFacts: Equatable, Sendable {
    public let url: URL
    public let isDirectory: Bool

    /// Whether the system treats this directory as one opaque thing rather than
    /// a folder to browse into — an `.app`, a `.photoslibrary`, an `.rtfd`, or
    /// any bundle type an installed app has registered with LaunchServices.
    ///
    /// This is macOS's own answer, not a list this app maintains, which is what
    /// lets a user add `sketch` to a category and have real Sketch documents
    /// routed there. Always `false` for a plain file, and — deliberately —
    /// `false` for a directory the system considers browsable, so a folder
    /// merely *named* `footage.mp4` is still not a video.
    public let isPackage: Bool

    public let creationDate: Date

    public init(url: URL, isDirectory: Bool, isPackage: Bool, creationDate: Date) {
        self.url = url
        self.isDirectory = isDirectory
        self.isPackage = isPackage
        self.creationDate = creationDate
    }

    /// Reads the real attributes. Returns nil if the item no longer exists.
    public init?(url: URL) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isPackageKey, .creationDateKey, .contentModificationDateKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        self.url = url
        self.isDirectory = values.isDirectory ?? false
        self.isPackage = values.isPackage ?? false
        self.creationDate = values.creationDate ?? values.contentModificationDate ?? Date()
    }
}
