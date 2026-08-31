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

// MARK: - Choosing a folder as a project

public extension Project {
    /// What choosing a folder means for an existing project list.
    struct Choice: Equatable, Sendable {
        /// The list to save. Identical to the input when the folder was
        /// already a project.
        public let projects: [Project]
        /// The project to make active. When the folder was already known this
        /// is the *existing* project, not a fresh one, so a caller can never
        /// activate an id that is absent from `projects`.
        public let project: Project
        /// Whether the folder was already a project.
        public let wasAlreadyKnown: Bool
    }

    /// A project is identified by its folder, not by its id.
    ///
    /// `Project(folder:)` mints a fresh `UUID` on every call, so a caller that
    /// appends unconditionally grows the list by one indistinguishable entry
    /// each time the user picks a folder they have already picked: two menu
    /// rows with the same name pointing at the same place, and only the newest
    /// of them active. Choosing a folder that is already a project therefore
    /// re-selects the existing project and leaves the list untouched.
    ///
    /// Folders are compared by resolved, standardized path, so one directory
    /// reached by a trailing slash, a `..` component, or a symlink counts once.
    /// The symlink case is not hypothetical on macOS: `/tmp` and `/var` are
    /// symlinks into `/private`, and an open panel can hand back either form.
    static func choosing(_ folder: URL, in projects: [Project]) -> Choice {
        let key = folderKey(folder)
        if let existing = projects.first(where: { folderKey($0.folder) == key }) {
            return Choice(projects: projects, project: existing, wasAlreadyKnown: true)
        }
        let project = Project(folder: folder)
        return Choice(projects: projects + [project], project: project, wasAlreadyKnown: false)
    }

    /// Two URLs name the same project folder when this matches.
    ///
    /// `resolvingSymlinksInPath()` reads the filesystem, and for a path that
    /// does not exist it resolves the part that does and leaves the rest
    /// alone. That is the behaviour we want here rather than a limitation: a
    /// project whose folder has been deleted or unmounted still compares equal
    /// to itself, so it is never silently duplicated while it is away.
    private static func folderKey(_ folder: URL) -> String {
        folder.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
