import Foundation

public enum SettleResult: Equatable, Sendable {
    /// Finished and safe to move.
    case ready
    /// Not this time; the caller may re-queue.
    case stillWriting
    /// Not a candidate at all (in-progress extension, hidden, or gone).
    case ignored
    /// Still changing after the ceiling elapsed. Left alone.
    case gaveUp
}

/// Decides when a newly appeared file has finished downloading.
///
/// Browsers write partial downloads under a placeholder extension and rename on
/// completion, but not all of them do, and none of them announce it — so this
/// combines an extension blocklist with size-stability sampling and a
/// coordinated read that respects apps holding the file open.
public struct DownloadSettler: Sendable {
    /// Extensions browsers and download managers use for work in progress.
    public static let inProgressExtensions: Set<String> = [
        "crdownload", "part", "partial", "download", "tmp", "opdownload", "!ut"
    ]

    private let sampleInterval: Duration
    private let ceiling: Duration

    public init(sampleInterval: Duration = .seconds(2), ceiling: Duration = .seconds(300)) {
        self.sampleInterval = sampleInterval
        self.ceiling = ceiling
    }

    public static func isIgnored(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        if name.hasPrefix(".") { return true }
        return inProgressExtensions.contains(url.pathExtension.lowercased())
    }

    public func settle(_ url: URL) async -> SettleResult {
        guard !Self.isIgnored(url),
              FileManager.default.fileExists(atPath: url.path)
        else { return .ignored }

        let deadline = ContinuousClock.now.advanced(by: ceiling)
        var previous = Self.size(of: url)

        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: sampleInterval)

            guard FileManager.default.fileExists(atPath: url.path) else { return .ignored }
            let current = Self.size(of: url)

            if current == previous {
                return Self.canReadWithoutContention(url) ? .ready : .stillWriting
            }
            previous = current
        }
        return .gaveUp
    }

    /// Reads the file's current size from disk.
    ///
    /// Deliberately uses `FileManager.attributesOfItem` rather than
    /// `URL.resourceValues(forKeys:)`: a `URL` value caches resource values
    /// after the first fetch, so repeated calls on the same `URL` (as this
    /// polling loop makes) would keep returning the size from the very first
    /// sample forever, never seeing the file grow. `attributesOfItem` always
    /// re-stats the file.
    private static func size(of url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Best-effort check that no coordinating app holds the file. Apps that use
    /// NSFileCoordinator (most Apple apps, iCloud-aware apps) will block here;
    /// apps that do not are covered by the size-stability check above.
    private static func canReadWithoutContention(_ url: URL) -> Bool {
        let semaphore = DispatchSemaphore(value: 0)
        var succeeded = false

        DispatchQueue.global(qos: .utility).async {
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(
                readingItemAt: url, options: .withoutChanges, error: &coordinationError
            ) { _ in
                succeeded = true
            }
            semaphore.signal()
        }

        return semaphore.wait(timeout: .now() + 3) == .success && succeeded
    }
}
