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
        let name = facts.url.lastPathComponent
        let ext = facts.url.pathExtension.lowercased()

        // A folder named "footage.mp4" is not a video. A directory matches only
        // when a rule claims it *and* the system reports it as a package — see
        // `FileFacts.isPackage`. Asking macOS, rather than checking a list this
        // app maintains, is what lets a user add `sketch` to a category and
        // have real Sketch documents routed there instead of silently landing
        // in the fallback.
        //
        // The old `!ext.isEmpty` guard is gone: a pattern-only rule can claim a
        // file with no extension, and an extension rule still cannot, because
        // an empty `ext` matches no entry in any extension list.
        guard !(facts.isDirectory && !facts.isPackage),
              let category = rules.categories.first(where: {
                  $0.matches(name: name, extension: ext)
              })
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
            // A pattern-only rule can now reach here with nothing to subdivide
            // by. Appending an empty component would build a folder whose name
            // is the empty string.
            if !ext.isEmpty { folder.appendPathComponent(ext.uppercased()) }
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
