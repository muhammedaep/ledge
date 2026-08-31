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
        self.storage = Self.read(from: directory.appendingPathComponent("journal.json"))
    }

    public static func applicationSupport(cap: Int = 200) -> MoveJournal {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Ledge", isDirectory: true)
        return MoveJournal(directory: base, cap: cap)
    }

    private var fileURL: URL { directory.appendingPathComponent("journal.json") }

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

    public func remove(batchID: UUID) throws {
        storage.removeAll { $0.batchID == batchID }
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
        return records.sorted { $0.date > $1.date }
    }
}
