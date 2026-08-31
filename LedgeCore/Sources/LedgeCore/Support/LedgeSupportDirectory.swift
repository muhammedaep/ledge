import Foundation

/// The one place that knows where Ledge keeps its data.
///
/// `RulesStore`, `MoveJournal` and `ProjectStore` all persist into the same
/// folder, and each of them used to derive the path itself. Three copies of one
/// derivation can drift — a `ledge` where the others say `Ledge`, or
/// `.documentDirectory` for `.applicationSupportDirectory` — and the failure is
/// quiet: the store that drifted comes up empty on the next launch, with no
/// crash and no error, while the user's real data sits untouched where it was
/// left. Deriving it once means there is nothing left to disagree about.
///
/// Found by mutation rather than by review: changing this folder name in any one
/// store killed no test, because no test can construct those factories without
/// resolving into the user's real home directory.
enum LedgeSupportDirectory {
    /// `~/Library/Application Support/Ledge`
    ///
    /// Computed, never created. Callers create it when they first write, which
    /// is what keeps a merely-launched Ledge from leaving a folder behind.
    static var url: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
    }
}
