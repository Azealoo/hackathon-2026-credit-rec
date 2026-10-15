import Foundation
import Synchronization

/// `CheckRecord` files in `<container>/checks/` (SPEC §15.5). Thread-safe within a process: every read-modify-write
/// runs under one lock, and files are written atomically so the widget never reads half a record.
/// Records older than 24 h are pruned on every write.
final class CheckStore: Sendable {
    static let maxAge: TimeInterval = 24 * 60 * 60

    enum StoreError: Error, Equatable {
        case invalidCheckId
        case notFound
    }

    /// `<container>/checks`
    let directory: URL
    private let lock = Mutex(())

    init(containerURL: URL) {
        directory = containerURL.appending(path: "checks", directoryHint: .isDirectory)
    }

    static let appGroup = CheckStore(containerURL: AppGroup.containerURL)

    // MARK: Reading

    func record(id checkId: String) -> CheckRecord? {
        guard let url = fileURL(for: checkId) else { return nil }
        return lock.withLock { _ in Self.read(url) }
    }

    /// The most recently created record that hasn't expired.
    func latest(now: Date = .now) -> CheckRecord? {
        lock.withLock { _ in
            allRecords()
                .filter { ($0.createdDate ?? .distantPast) > now.addingTimeInterval(-Self.maxAge) }
                .max { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }
        }
    }

    func all() -> [CheckRecord] {
        lock.withLock { _ in allRecords() }
    }

    // MARK: Writing

    func write(_ record: CheckRecord, now: Date = .now) throws {
        guard let url = fileURL(for: record.checkId) else { throw StoreError.invalidCheckId }
        try lock.withLock { _ in
            try Self.save(record, to: url, directory: directory)
            pruneLocked(now: now)
        }
    }

    /// Atomically loads, changes and saves one record. `body` runs under the store's lock, so two updates of the
    /// same record never interleave. Returns the saved record.
    @discardableResult
    func update(id checkId: String, _ body: (inout CheckRecord) throws -> Void) throws -> CheckRecord {
        guard let url = fileURL(for: checkId) else { throw StoreError.invalidCheckId }
        return try lock.withLock { _ in
            guard var record = Self.read(url) else { throw StoreError.notFound }
            try body(&record)
            try Self.save(record, to: url, directory: directory)
            return record
        }
    }

    func prune(now: Date = .now) {
        lock.withLock { _ in pruneLocked(now: now) }
    }

    // MARK: Private (call with the lock held)

    private func fileURL(for checkId: String) -> URL? {
        // The ID comes from intent parameters; never let it name a path outside the folder.
        guard !checkId.isEmpty, checkId.count <= 64,
              checkId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") })
        else { return nil }
        return directory.appending(path: "\(checkId).json", directoryHint: .notDirectory)
    }

    private func recordFiles() -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]
        )) ?? []
        return urls.filter { $0.pathExtension == "json" }
    }

    private func allRecords() -> [CheckRecord] {
        recordFiles().compactMap(Self.read)
    }

    private func pruneLocked(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.maxAge)
        for url in recordFiles() {
            let created = Self.read(url)?.createdDate
                ?? (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                ?? .distantPast
            if created < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private static func read(_ url: URL) -> CheckRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CheckRecord.self, from: data)
    }

    private static func save(_ record: CheckRecord, to url: URL, directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONCoding.encoder.encode(record).write(to: url, options: [.atomic])
    }
}
