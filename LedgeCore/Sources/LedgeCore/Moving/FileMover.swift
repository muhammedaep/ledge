import Foundation

public enum MoveError: Error, Equatable {
    case sourceMissing(URL)
    case destinationNotWritable(URL)
    case underlying(String)
}

/// The only component that mutates the filesystem.
///
/// Invariant: this never overwrites anything. On a name collision it inserts
/// " (1)", " (2)", … before the extension. Undo relies on the same guarantee,
/// so undoing into a folder that has since gained a same-named file is safe.
public struct FileMover: Sendable {
    public init() {}

    @discardableResult
    public func move(_ source: URL, into folder: URL) throws -> URL {
        let fm = FileManager.default

        var isDirectoryRef: ObjCBool = false
        guard fm.fileExists(atPath: source.path, isDirectory: &isDirectoryRef) else {
            throw MoveError.sourceMissing(source)
        }
        let sourceIsDirectory = isDirectoryRef.boolValue

        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            throw MoveError.destinationNotWritable(folder)
        }

        let target = Self.availableURL(for: source.lastPathComponent, in: folder)

        do {
            try fm.moveItem(at: source, to: target)
        } catch {
            throw MoveError.underlying(error.localizedDescription)
        }

        // `URL.appendingPathComponent(_:)` consults the filesystem when no
        // `isDirectory` hint is given, so once the move lands, any URL a
        // caller builds the same way for this path resolves with a trailing
        // slash for a directory. Match that here so callers can compare the
        // returned URL for equality against one they construct themselves.
        return URL(fileURLWithPath: target.path, isDirectory: sourceIsDirectory)
    }

    /// The first free name in `folder` based on `name`.
    public static func availableURL(for name: String, in folder: URL) -> URL {
        let fm = FileManager.default
        let candidate = folder.appendingPathComponent(name)
        guard fm.fileExists(atPath: candidate.path) else { return candidate }

        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension

        var counter = 1
        while true {
            let numbered = ext.isEmpty ? "\(stem) (\(counter))" : "\(stem) (\(counter)).\(ext)"
            let url = folder.appendingPathComponent(numbered)
            if !fm.fileExists(atPath: url.path) { return url }
            counter += 1
        }
    }
}
