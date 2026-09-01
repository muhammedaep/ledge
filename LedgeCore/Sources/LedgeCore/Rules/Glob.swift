import Foundation

/// Matches a filename against a shell-style pattern.
///
/// Two metacharacters and no escaping: `*` for any run of characters including
/// none, `?` for exactly one. That is the whole language. Character classes and
/// escaping would double this file's surface to serve filenames nobody has, and
/// a pattern a user cannot predict is worse than one they cannot write.
///
/// Not `fnmatch(3)`: its case-insensitive flag `FNM_CASEFOLD` is a BSD
/// extension, it folds bytes rather than characters, and its behaviour is not
/// something these tests could pin down.
public enum Glob {
    /// Whether `name` matches `pattern`, folding case.
    ///
    /// `lowercased()` and deliberately not `lowercased(with: Locale.current)`.
    /// Under a Turkish locale the latter maps `I` to `ı`, so a pattern written
    /// on a Turkish Mac would stop matching the same file on an English one.
    /// `lowercased()` is locale-independent: both sides fold identically, and
    /// accented letters still match their capitals.
    ///
    /// Compares `Character`s rather than unicode scalars, so `?` matches one
    /// grapheme — one thing the user would call a character — rather than
    /// splitting an emoji or a combining sequence in half.
    public static func matches(pattern: String, name: String) -> Bool {
        let p = Array(pattern.lowercased())
        let s = Array(name.lowercased())

        var pi = 0
        var si = 0
        // Where the most recent `*` sat, and how much of the name it had
        // consumed. Backtracking to here is what lets a later literal fail
        // without failing the whole match.
        var lastStar = -1
        var lastStarConsumed = 0

        while si < s.count {
            if pi < p.count, p[pi] == "?" || p[pi] == s[si] {
                pi += 1
                si += 1
            } else if pi < p.count, p[pi] == "*" {
                lastStar = pi
                lastStarConsumed = si
                pi += 1
            } else if lastStar >= 0 {
                lastStarConsumed += 1
                si = lastStarConsumed
                pi = lastStar + 1
            } else {
                return false
            }
        }

        // Trailing `*`s have nothing left to consume and match the empty rest.
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }
}
