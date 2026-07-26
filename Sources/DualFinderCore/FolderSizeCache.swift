import Foundation

public enum FolderSizeResolution: Equatable, Sendable {
    case cached(Int64)
    case computed(Int64)

    public var size: Int64 {
        switch self {
        case .cached(let size), .computed(let size):
            size
        }
    }
}

public final class FolderSizeCache: @unchecked Sendable {
    public static let defaultMaxEntries = 2_000
    public static let defaultDebounceInterval: TimeInterval = 1.0

    private struct Entry: Codable {
        var size: Int64
        var modifiedAt: Date
    }

    private let storageURL: URL
    private let fileManager: FileManager
    private let maxEntries: Int
    private let debounceInterval: TimeInterval
    private let lock = NSLock()
    private var entries: [String: Entry]
    private var accessOrder = OrderedAccessTracker<String>()
    private var pendingSave: DispatchWorkItem?
    private let saveQueue = DispatchQueue(label: "DualFinder.FolderSizeCache.save")

    public init(
        storageURL: URL = FolderSizeCache.defaultStorageURL(),
        fileManager: FileManager = .default,
        maxEntries: Int = FolderSizeCache.defaultMaxEntries,
        debounceInterval: TimeInterval = FolderSizeCache.defaultDebounceInterval
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        self.maxEntries = max(1, maxEntries)
        self.debounceInterval = max(0, debounceInterval)
        entries = Self.load(from: storageURL)
        for key in entries.keys {
            accessOrder.touch(key)
        }
        trimEntriesIfNeeded()
    }

    public func size(for folder: URL, modifiedAt: Date?) -> Int64? {
        guard let modifiedAt else { return nil }
        let key = normalizedPath(for: folder)
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[key], entry.modifiedAt == modifiedAt else { return nil }
        touchEntry(key: key)
        return entry.size
    }

    public func setSize(_ size: Int64, for folder: URL, modifiedAt: Date?) throws {
        guard let modifiedAt else { return }
        let key = normalizedPath(for: folder)
        lock.lock()
        entries[key] = Entry(size: size, modifiedAt: modifiedAt)
        touchEntry(key: key)
        trimEntriesIfNeeded()
        lock.unlock()
        scheduleDebouncedSave()
    }

    public func flush() throws {
        let snapshot: [String: Entry]
        lock.lock()
        pendingSave?.cancel()
        pendingSave = nil
        snapshot = entries
        lock.unlock()
        try save(snapshot)
    }

    public var entryCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return entries.count
    }

    public static func defaultStorageURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base
            .appendingPathComponent("DualFinder", isDirectory: true)
            .appendingPathComponent("folder-size-cache.json")
    }

    private static func load(from url: URL) -> [String: Entry] {
        guard let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([String: Entry].self, from: data)
        else {
            return [:]
        }
        return entries
    }

    private func save(_ entries: [String: Entry]) throws {
        try fileManager.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(entries)
        try data.write(to: storageURL, options: [.atomic])
    }

    private func scheduleDebouncedSave() {
        lock.lock()
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.performDebouncedSave()
        }
        pendingSave = work
        lock.unlock()
        saveQueue.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    private func performDebouncedSave() {
        lock.lock()
        pendingSave = nil
        let latestSnapshot = entries
        lock.unlock()
        try? save(latestSnapshot)
    }

    private func normalizedPath(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }

    private func touchEntry(key: String) {
        accessOrder.touch(key)
    }

    private func trimEntriesIfNeeded() {
        while entries.count > maxEntries, let oldest = accessOrder.removeOldest() {
            entries.removeValue(forKey: oldest)
        }
    }
}
