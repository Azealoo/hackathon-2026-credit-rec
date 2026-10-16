import Foundation
import Synchronization

/// `CheckRecord` files in `<container>/checks/` (SPEC §15.5). Thread-safe within a process: every read-modify-write
/// runs under one lock, and files are written atomically so the widget never reads half a record.
/// Records older than 24 h are pruned on every write and on app launch (`prune`), and every read leaves them out, so
/// a record past 24 h never shows (What we sent, a snippet, a save) even before the files go.
final class CheckStore: Sendable {
    static let maxAge: TimeInterval = 24 * 60 * 60

    enum StoreError: Error, Equatable {
        case invalidCheckId
        case notFound
    }

    /// `<container>/checks`
    let directory: URL
    /// The clock reads are aged against (tests pass a fixed one).
    private let now: @Sendable () -> Date
    private let lock = Mutex(())

    init(containerURL: URL, now: @escaping @Sendable () -> Date = { .now }) {
        directory = containerURL.appending(path: "checks", directoryHint: .isDirectory)
        self.now = now
    }

    static let appGroup = CheckStore(containerURL: AppGroup.containerURL)

    // MARK: Reading

    /// The record, unless it has expired.
    func record(id checkId: String, now: Date? = nil) -> CheckRecord? {
        guard let url = fileURL(for: checkId) else { return nil }
        let cutoff = cutoff(now)
        return lock.withLock { _ in Self.read(url).flatMap { Self.isLive($0, cutoff: cutoff) ? $0 : nil } }
    }

    /// The most recently created record that hasn't expired.
    func latest(now: Date? = nil) -> CheckRecord? {
        all(now: now).max { ($0.createdDate ?? .distantPast) < ($1.createdDate ?? .distantPast) }
    }

    /// Every record that hasn't expired.
    func all(now: Date? = nil) -> [CheckRecord] {
        let cutoff = cutoff(now)
        return lock.withLock { _ in allRecords().filter { Self.isLive($0, cutoff: cutoff) } }
    }

    /// Every record that hasn't expired, the newest first ("What we sent").
    func newestFirst(now: Date? = nil) -> [CheckRecord] {
        all(now: now).sorted {
            ($0.createdDate ?? .distantPast, $0.checkId) > ($1.createdDate ?? .distantPast, $1.checkId)
        }
    }

    // MARK: Writing

    func write(_ record: CheckRecord, now: Date? = nil) throws {
        guard let url = fileURL(for: record.checkId) else { throw StoreError.invalidCheckId }
        let now = now ?? self.now()
        try lock.withLock { _ in
            try Self.save(record, to: url, directory: directory)
            pruneLocked(now: now)
        }
    }

    /// Atomically loads, changes and saves one record. `body` runs under the store's lock, so two updates of the
    /// same record never interleave. Returns the saved record. An expired record is `notFound`.
    @discardableResult
    func update(id checkId: String, now: Date? = nil, _ body: (inout CheckRecord) throws -> Void) throws -> CheckRecord {
        guard let url = fileURL(for: checkId) else { throw StoreError.invalidCheckId }
        let cutoff = cutoff(now)
        return try lock.withLock { _ in
            guard var record = Self.read(url), Self.isLive(record, cutoff: cutoff) else { throw StoreError.notFound }
            try body(&record)
            try Self.save(record, to: url, directory: directory)
            return record
        }
    }

    /// Deletes every record (the debug `-resetState` launch argument).
    func removeAll() {
        lock.withLock { _ in
            for url in recordFiles() {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    /// Deletes every record older than 24 h (run on app launch, and after every write).
    func prune(now: Date? = nil) {
        let now = now ?? self.now()
        lock.withLock { _ in pruneLocked(now: now) }
    }

    // MARK: Private (call with the lock held)

    private func cutoff(_ now: Date?) -> Date {
        (now ?? self.now()).addingTimeInterval(-Self.maxAge)
    }

    /// Created after `cutoff`. A record whose timestamp can't be read can't be aged, so it counts as expired (as
    /// `latest` always treated it).
    private static func isLive(_ record: CheckRecord, cutoff: Date) -> Bool {
        (record.createdDate ?? .distantPast) > cutoff
    }

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
