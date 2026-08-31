import Foundation

public struct Destination: Equatable, Sendable {
    public let folder: URL
    public let category: String

    public init(folder: URL, category: String) {
        self.folder = folder
        self.category = category
    }
}

/// Pure mapping from a file to where it belongs. No filesystem access.
public enum Categorizer {
    public static func destination(
        for facts: FileFacts,
        in root: URL,
        using rules: RuleSet
    ) -> Destination {
        let ext = facts.url.pathExtension.lowercased()

        // A folder named "footage.mp4" is not a video. A directory matches only
        // when a rule claims its extension *and* the system reports it as a
        // package — see `FileFacts.isPackage`. Asking macOS, rather than
        // checking a list this app maintains, is what lets a user add `sketch`
        // to a category and have real Sketch documents routed there instead of
        // silently landing in the fallback.
        guard !ext.isEmpty,
              let category = rules.categories.first(where: { $0.extensions.contains(ext) }),
              !(facts.isDirectory && !facts.isPackage)
        else {
            return Destination(
                folder: root.appendingPathComponent(rules.fallbackName),
                category: rules.fallbackName
            )
        }

        var folder = root.appendingPathComponent(category.name)
        switch category.subdivision {
        case .none:
            break
        case .byExtension:
            folder.appendPathComponent(ext.uppercased())
        case .byMonth:
            folder.appendPathComponent(Self.monthFormatter.string(from: facts.creationDate))
        }

        return Destination(folder: folder, category: category.name)
    }

    private static let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM"
        return f
    }()
}
