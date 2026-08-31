import Foundation

/// How a category splits its folder into subfolders.
public enum Subdivision: String, Codable, CaseIterable, Sendable {
    /// Everything goes directly in the category folder.
    case none
    /// `Images/PNG/`, `Images/JPG/` …
    case byExtension
    /// `Images/2026-08/` …
    case byMonth
}

/// One filing rule: a destination folder name and the extensions that belong in it.
public struct Category: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var name: String
    public var extensions: [String]
    public var subdivision: Subdivision

    public init(
        id: UUID = UUID(),
        name: String,
        extensions: [String],
        subdivision: Subdivision = .none
    ) {
        self.id = id
        self.name = name
        self.extensions = extensions.map { $0.lowercased() }
        self.subdivision = subdivision
    }
}
