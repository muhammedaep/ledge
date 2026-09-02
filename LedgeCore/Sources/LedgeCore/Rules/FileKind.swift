import Foundation
import UniformTypeIdentifiers

/// The visual family a file belongs to, for the badge the shelf draws.
///
/// Read from the extension, never from the category the file was filed into: a
/// screenshot filed into `Screenshots` is still a PNG, and a badge that changed
/// colour depending on which rule happened to claim the file would be a rule no
/// user could predict.
///
/// Asks macOS rather than carrying a list. `psd` is an image and nobody would
/// think to write that down; a format released next year is classified
/// correctly by a system that has been taught about it, by a lookup nobody has
/// to maintain.
public enum FileKind: Sendable, Equatable {
    case image
    case movie
    case document
    case other

    /// The family for a filename extension, with or without case.
    ///
    /// Order is load-bearing. An image conforms to `public.content` as surely as
    /// a PDF does, so asking about content first would swallow every image and
    /// every video into the document family. The specific questions come first
    /// and the general one last.
    ///
    /// The document family is `public.content` — "something a person opens and
    /// reads" — and deliberately not `public.data`, which is every byte on the
    /// disk including archives, fonts and application bundles. Those get the
    /// neutral badge, which is the honest answer for things that are not
    /// documents.
    public static func of(extension ext: String) -> FileKind {
        guard let type = UTType(filenameExtension: ext.lowercased()) else { return .other }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) { return .movie }
        if type.conforms(to: .content) { return .document }
        return .other
    }
}
