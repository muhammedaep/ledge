import Testing
@testable import LedgeCore

@Test func imagesAreImages() {
    #expect(FileKind.of(extension: "png") == .image)
    #expect(FileKind.of(extension: "jpg") == .image)
    #expect(FileKind.of(extension: "heic") == .image)
    #expect(FileKind.of(extension: "svg") == .image)
}

@Test func moviesAreMovies() {
    #expect(FileKind.of(extension: "mov") == .movie)
    #expect(FileKind.of(extension: "mp4") == .movie)
}

@Test func readableDocumentsAreDocuments() {
    #expect(FileKind.of(extension: "pdf") == .document)
    #expect(FileKind.of(extension: "txt") == .document)
    #expect(FileKind.of(extension: "key") == .document)
}

@Test func archivesAndAppsAndFontsAreNeitherOfThose() {
    // They conform to `public.data`, not `public.content`, which is the
    // distinction the document family rests on.
    #expect(FileKind.of(extension: "zip") == .other)
    #expect(FileKind.of(extension: "app") == .other)
    #expect(FileKind.of(extension: "ttf") == .other)
}

@Test func anExtensionMacOSHasNeverHeardOfIsOther() {
    #expect(FileKind.of(extension: "aep") == .other)
    #expect(FileKind.of(extension: "zzzznotathing") == .other)
}

@Test func noExtensionIsOther() {
    #expect(FileKind.of(extension: "") == .other)
}

@Test func theLookupFoldsCase() {
    #expect(FileKind.of(extension: "PNG") == .image)
    #expect(FileKind.of(extension: "Mov") == .movie)
}

@Test func aFormatThatIsAnImageWithoutSayingSoInItsNameIsStillAnImage() {
    // The reason this is a UTType lookup and not a list: nobody would think
    // to put `psd` in an image list, and macOS already knows.
    #expect(FileKind.of(extension: "psd") == .image)
}
