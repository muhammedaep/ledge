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
    /// The settle was cancelled *while sampling*, before reaching a conclusion
    /// — the app quit, or the watcher restarted because the user changed a
    /// watched folder. Unlike the other four cases this says nothing about the
    /// file itself; the caller should re-queue it once running again.
    ///
    /// Deliberately not the whole cancellation story: a settle cancelled inside
    /// the coordinated read reports `.stillWriting` instead. Cancelling the
    /// coordinator fails the pending read, and a failed coordination is
    /// indistinguishable from a claim this settle genuinely lost — so the
    /// conservative answer wins. Both mean the same thing to the caller ("do
    /// not move it; ask again later"), which is why the distinction is not
    /// worth inventing a fifth outcome for.
    case cancelled
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
    private let sizeProvider: @Sendable (URL) -> Int64

    public init(
        sampleInterval: Duration = .seconds(2),
        ceiling: Duration = .seconds(300),
        sizeProvider: @escaping @Sendable (URL) -> Int64 = DownloadSettler.fileSize
    ) {
        self.sampleInterval = sampleInterval
        self.ceiling = ceiling
        self.sizeProvider = sizeProvider
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

        // Checked before each sleep, not after, so a settle that is still
        // sampling when the deadline passes can overshoot `ceiling` by up to
        // one `sampleInterval` before it gives up.
        let deadline = ContinuousClock.now.advanced(by: ceiling)
        var previous = sizeProvider(url)

        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: sampleInterval)
            // `Task.sleep` throws (and `try?` above swallows) `CancellationError`
            // immediately once the task is cancelled, without actually waiting —
            // so without this check a cancelled settle would busy-spin through
            // this loop as fast as the CPU allows, sampling continuously until
            // `deadline`, instead of stopping when its caller stops caring.
            if Task.isCancelled { return .cancelled }

            guard FileManager.default.fileExists(atPath: url.path) else { return .ignored }
            let current = sizeProvider(url)

            if current == previous {
                return await Self.canReadWithoutContention(url) ? .ready : .stillWriting
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
    public static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? -1
    }

    /// Best-effort check that no coordinating app holds the file. Apps that use
    /// NSFileCoordinator (most Apple apps, iCloud-aware apps) will have their
    /// claim respected here; apps that do not are covered by the size-stability
    /// check above.
    ///
    /// Uses the asynchronous `coordinate(with:queue:byAccessor:)` rather than
    /// the synchronous `coordinate(readingItemAt:options:error:byAccessor:)`
    /// wrapped in a hand-rolled semaphore wait: the synchronous form has to run
    /// on a background queue and be waited on with a timeout, which (a) leaves
    /// the coordinated read running and its thread blocked indefinitely if the
    /// timeout fires first, (b) has no way to propagate this call's priority to
    /// that background work, and (c) required a `var succeeded` mutated from
    /// inside the coordinator's callback, which is a data race the compiler
    /// already flagged.
    ///
    /// A pending coordinated read waits for a conflicting claim to be released
    /// rather than failing fast — measured directly against a real writer
    /// holding a write claim, the read's completion handler simply doesn't
    /// fire until the writer does. Left alone, that means this call is
    /// unbounded: it does not return until either read succeeds or `deadline`
    /// forces the caller to give up on the *whole* settle, however long that
    /// coordinated wait takes. `withTaskCancellationHandler` makes it respect
    /// cancellation specifically: calling `coordinator.cancel()` interrupts a
    /// pending (not-yet-granted) request and fails it promptly, so a cancelled
    /// settle returns promptly here too instead of waiting out someone else's
    /// claim.
    ///
    /// `error` from the accessor is deliberately not surfaced: any coordination
    /// failure — including cancellation, or another process not responding —
    /// is treated the same as unresolved contention. Better to wait for one
    /// more sample than to file a document another app might still be writing to.
    private static func canReadWithoutContention(_ url: URL) async -> Bool {
        let intent = NSFileAccessIntent.readingIntent(with: url, options: .withoutChanges)
        // NSFileCoordinator predates Sendable and isn't annotated, but calling
        // `cancel()` from a different thread than the one that started the
        // coordinated access is exactly its documented cross-thread purpose.
        nonisolated(unsafe) let coordinator = NSFileCoordinator()
        let queue = OperationQueue()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                coordinator.coordinate(with: [intent], queue: queue) { error in
                    continuation.resume(returning: error == nil)
                }
            }
        } onCancel: {
            coordinator.cancel()
        }
    }
}
