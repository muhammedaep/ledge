import Testing
import Foundation
@testable import LedgeCore

/// The single derivation of where Ledge keeps its data, shared by `RulesStore`,
/// `MoveJournal` and `ProjectStore`. Getting it wrong orphans a store's data
/// silently — the app comes up empty while the user's real file sits untouched
/// somewhere else — so it is worth pinning even though it is four lines.
///
/// **Nothing here touches the filesystem.** The URL is asserted, never created:
/// a test that made this directory would write into the user's real `~/Library`,
/// which is precisely what `TempDirectory` exists to prevent.
///
/// The expectations are derived independently rather than by calling the same
/// helper and comparing it with itself. `"Ledge"` and `"Application Support"`
/// are literals, and `NSHomeDirectory()` is a different API from the
/// `FileManager.urls(for:in:)` the code uses — so this cannot agree with a
/// mistake by making it twice.
@Test func supportDirectoryIsLedgesOwnFolderInsideApplicationSupport() {
    let url = LedgeSupportDirectory.url

    #expect(url.lastPathComponent == "Ledge",
            "the folder Ledge owns; every store appends its file name to this")
    #expect(url.hasDirectoryPath,
            "a directory URL, since stores append file names to it")
    #expect(url.pathComponents.contains("Application Support"),
            "Application Support, not Documents or Caches: \(url.path)")
    #expect(url.path.hasPrefix(NSHomeDirectory()),
            "the user's own domain, not the system one: \(url.path)")
}

/// The directory is derived on demand and must not be a stale snapshot.
@Test func supportDirectoryIsStableAcrossCalls() {
    #expect(LedgeSupportDirectory.url == LedgeSupportDirectory.url)
}
