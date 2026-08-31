import Foundation

/// An inert description of a file, so categorization never has to touch the disk.
public struct FileFacts: Equatable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    public let creationDate: Date

    public init(url: URL, isDirectory: Bool, creationDate: Date) {
        self.url = url
        self.isDirectory = isDirectory
        self.creationDate = creationDate
    }

    /// Reads the real attributes. Returns nil if the item no longer exists.
    public init?(url: URL) {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey, .contentModificationDateKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return nil }
        self.url = url
        self.isDirectory = values.isDirectory ?? false
        self.creationDate = values.creationDate ?? values.contentModificationDate ?? Date()
    }
}
