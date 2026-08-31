import Foundation

/// A unique directory under the system temp dir, removed when this object dies.
/// Every test that touches the filesystem uses one of these — no test ever
/// writes into a real user folder.
final class TempDirectory {
    let url: URL

    init() throws {
        url = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("ledge-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    func writeFile(_ name: String, contents: String = "x") throws -> URL {
        let target = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    /// A symlink at `name` pointing at `target`, which does not have to exist.
    /// The dangling case is the interesting one: `fileExists` reports it
    /// absent, `lstat` reports it present, and `moveItem` moves it happily.
    @discardableResult
    func makeSymlink(_ name: String, to target: String) throws -> URL {
        let link = url.appendingPathComponent(name)
        try FileManager.default.createDirectory(
            at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target)
        return link
    }

    @discardableResult
    func makeDirectory(_ name: String) throws -> URL {
        let target = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
