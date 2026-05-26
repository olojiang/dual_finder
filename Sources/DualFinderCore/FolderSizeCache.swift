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
    private struct Entry: Codable {
        var size: Int64
        var modifiedAt: Date
    }

    private let storageURL: URL
    private let fileManager: FileManager
    private let lock = NSLock()
    private var entries: [String: Entry]

    public init(
        storageURL: URL = FolderSizeCache.defaultStorageURL(),
        fileManager: FileManager = .default
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        entries = Self.load(from: storageURL)
    }

    public func size(for folder: URL, modifiedAt: Date?) -> Int64? {
        guard let modifiedAt else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let entry = entries[normalizedPath(for: folder)] else { return nil }
        return entry.modifiedAt == modifiedAt ? entry.size : nil
    }

    public func setSize(_ size: Int64, for folder: URL, modifiedAt: Date?) throws {
        guard let modifiedAt else { return }
        lock.lock()
        entries[normalizedPath(for: folder)] = Entry(size: size, modifiedAt: modifiedAt)
        let snapshot = entries
        lock.unlock()
        try save(snapshot)
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

    private func normalizedPath(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }
}
