import Foundation

/// Append-only log of completed moves, capped and persisted on every write so
/// the shelf survives a crash. This is the sole source of truth for both the
/// shelf and undo.
public final class MoveJournal {
    private let directory: URL
    private let cap: Int
    private var storage: [MoveRecord] = []   // newest first

    public init(directory: URL, cap: Int = 200) {
        self.directory = directory
        self.cap = cap
        self.storage = Self.read(from: directory.appendingPathComponent(Self.fileName))
    }

    /// The app's real location. See `LedgeSupportDirectory`.
    public static func applicationSupport(cap: Int = 200) -> MoveJournal {
        MoveJournal(directory: LedgeSupportDirectory.url, cap: cap)
    }

    private static let fileName = "journal.json"
    private var fileURL: URL { directory.appendingPathComponent(Self.fileName) }

    public var records: [MoveRecord] { storage }

    public func append(_ record: MoveRecord) throws {
        storage.append(record)
        storage.sort { $0.date > $1.date }
        if storage.count > cap { storage = Array(storage.prefix(cap)) }
        try persist()
    }

    public func records(inBatch batchID: UUID) -> [MoveRecord] {
        storage.filter { $0.batchID == batchID }
    }

    public func remove(id: UUID) throws {
        storage.removeAll { $0.id == id }
        try persist()
    }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(storage).write(to: fileURL, options: .atomic)
    }

    private static func read(from url: URL) -> [MoveRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([MoveRecord].self, from: data) else { return [] }
        // A record's paths are what undo, drag-out and reveal act on, and
        // `URL` decodes `https://…` as happily as `file://…`. Anything that is
        // not a file URL never came from this app and is not acted on.
        return records
            .filter { $0.from.isFileURL && $0.to.isFileURL }
            .sorted { $0.date > $1.date }
    }
}
