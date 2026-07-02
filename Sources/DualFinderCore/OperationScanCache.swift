import Foundation

public struct OperationScanPlan: Equatable, Sendable {
    public let totalBytes: Int64
    public let totalItems: Int

    public init(totalBytes: Int64, totalItems: Int) {
        self.totalBytes = totalBytes
        self.totalItems = totalItems
    }
}

public final class OperationScanCache: @unchecked Sendable {
    private struct Entry: Codable {
        var totalBytes: Int64
        var totalItems: Int
        var modifiedAt: Date
        var cachedAt: Date
    }

    public static let defaultTTL: TimeInterval = 86_400

    private let storageURL: URL
    private let fileManager: FileManager
    private let ttl: TimeInterval
    private let dateProvider: () -> Date
    private let lock = NSLock()
    private var entries: [String: Entry]

    public init(
        storageURL: URL = OperationScanCache.defaultStorageURL(),
        fileManager: FileManager = .default,
        ttl: TimeInterval = OperationScanCache.defaultTTL,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        self.ttl = ttl
        self.dateProvider = dateProvider
        entries = Self.load(from: storageURL)
    }

    public func plan(for folder: URL, modifiedAt: Date?) -> OperationScanPlan? {
        guard let modifiedAt else { return nil }
        let now = dateProvider()
        lock.lock()
        defer { lock.unlock() }
        purgeExpiredEntries(olderThan: now.addingTimeInterval(-ttl))
        guard let entry = entries[normalizedPath(for: folder)],
              entry.modifiedAt == modifiedAt,
              entry.cachedAt >= now.addingTimeInterval(-ttl) else {
            return nil
        }
        return OperationScanPlan(totalBytes: entry.totalBytes, totalItems: entry.totalItems)
    }

    public func setPlan(_ plan: OperationScanPlan, for folder: URL, modifiedAt: Date?) throws {
        guard let modifiedAt else { return }
        let now = dateProvider()
        lock.lock()
        entries[normalizedPath(for: folder)] = Entry(
            totalBytes: plan.totalBytes,
            totalItems: plan.totalItems,
            modifiedAt: modifiedAt,
            cachedAt: now
        )
        purgeExpiredEntries(olderThan: now.addingTimeInterval(-ttl))
        let snapshot = entries
        lock.unlock()
        try save(snapshot)
    }

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base
            .appendingPathComponent("DualFinder", isDirectory: true)
            .appendingPathComponent("operation-scan-cache.json")
    }

    private func purgeExpiredEntries(olderThan cutoff: Date) {
        entries = entries.filter { $0.value.cachedAt >= cutoff }
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data) else {
            return [:]
        }
        return entries
    }

    private func save(_ entries: [String: Entry]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storageURL, options: [.atomic])
    }

    private func normalizedPath(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }
}
