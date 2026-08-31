import Foundation

/// Loads and saves the user's project list as JSON, mirroring RulesStore.
/// A corrupt file degrades to an empty list rather than crashing — losing the
/// project list is an inconvenience, a crash loop at launch is not.
public final class ProjectStore {
    private let directory: URL
    private let fileName = "projects.json"

    public init(directory: URL) {
        self.directory = directory
    }

    public static func applicationSupport() -> ProjectStore {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
        return ProjectStore(directory: base)
    }

    private var fileURL: URL { directory.appendingPathComponent(fileName) }

    public func load() -> [Project] {
        guard let data = try? Data(contentsOf: fileURL),
              let projects = try? JSONDecoder().decode([Project].self, from: data)
        else { return [] }
        return projects
    }

    public func save(_ projects: [Project]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(projects).write(to: fileURL, options: .atomic)
    }
}
