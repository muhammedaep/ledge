import Foundation

/// A folder the user has designated as a filing destination. While a project is
/// active, downloads are filed into it instead of into the watched folder, using
/// the same rules — so the project gains the same category subfolders.
public struct Project: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var folder: URL

    public init(id: UUID = UUID(), name: String? = nil, folder: URL) {
        self.id = id
        self.folder = folder
        self.name = name ?? folder.lastPathComponent
    }
}
