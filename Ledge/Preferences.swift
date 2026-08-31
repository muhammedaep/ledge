import Foundation
import Observation
import ServiceManagement

/// User settings, persisted to `UserDefaults` on every change.
@Observable
final class Preferences {
    private enum Key {
        static let watchedFolders = "watchedFolders"
        static let shelfSize = "shelfSize"
        static let automaticFiling = "automaticFilingEnabled"
        static let activeProjectID = "activeProjectID"
    }

    var watchedFolders: [URL] {
        didSet {
            UserDefaults.standard.set(watchedFolders.map(\.path), forKey: Key.watchedFolders)
        }
    }

    var shelfSize: Int {
        didSet { UserDefaults.standard.set(shelfSize, forKey: Key.shelfSize) }
    }

    var automaticFilingEnabled: Bool {
        didSet { UserDefaults.standard.set(automaticFilingEnabled, forKey: Key.automaticFiling) }
    }

    /// The project downloads are currently filed into, or nil for the watched
    /// folder. Stored as an id rather than a `Project` so the project list stays
    /// the single source of truth for the projects themselves.
    var activeProjectID: UUID? {
        didSet {
            UserDefaults.standard.set(activeProjectID?.uuidString, forKey: Key.activeProjectID)
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard launchAtLogin != (SMAppService.mainApp.status == .enabled) else { return }
            do {
                if launchAtLogin {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                // Assigning inside `didSet` does not re-enter it, so this
                // snaps the toggle back to what the system actually reports
                // rather than leaving the UI claiming a state that failed.
                launchAtLogin = SMAppService.mainApp.status == .enabled
            }
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let saved = defaults.stringArray(forKey: Key.watchedFolders) ?? []
        watchedFolders = saved.isEmpty
            ? [FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]]
            : saved.map { URL(fileURLWithPath: $0) }

        let size = defaults.integer(forKey: Key.shelfSize)
        shelfSize = size == 0 ? 10 : size

        automaticFilingEnabled = defaults.object(forKey: Key.automaticFiling) as? Bool ?? true
        activeProjectID = defaults.string(forKey: Key.activeProjectID)
            .flatMap(UUID.init(uuidString:))
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
