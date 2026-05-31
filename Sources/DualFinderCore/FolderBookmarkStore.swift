import Foundation

public struct FolderBookmarkEntry: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isFavorite: Bool

    public init(url: URL, isFavorite: Bool) {
        self.url = url
        self.isFavorite = isFavorite
    }

    public var id: String {
        url.standardizedFileURL.path
    }
}

public final class FolderBookmarkStore {
    private struct Snapshot: Codable, Equatable {
        var recentPaths: [String]
        var favoritePaths: [String]
    }

    private let defaults: UserDefaults
    private let key: String
    private let maxRecentCount: Int

    public init(defaults: UserDefaults = .standard, key: String = "folderBookmarks", maxRecentCount: Int = 100) {
        self.defaults = defaults
        self.key = key
        self.maxRecentCount = maxRecentCount
    }

    public func entries() -> [FolderBookmarkEntry] {
        let snapshot = loadSnapshot()
        let favoritePathSet = Set(snapshot.favoritePaths)
        let favoriteEntries = snapshot.favoritePaths.map {
            FolderBookmarkEntry(url: URL(fileURLWithPath: $0), isFavorite: true)
        }
        let recentEntries = snapshot.recentPaths
            .filter { !favoritePathSet.contains($0) }
            .map { FolderBookmarkEntry(url: URL(fileURLWithPath: $0), isFavorite: false) }

        return favoriteEntries + recentEntries
    }

    public func recordRecentFolder(_ url: URL) {
        var snapshot = loadSnapshot()
        let path = normalizedPath(for: url)
        snapshot.recentPaths.removeAll { $0 == path }
        snapshot.recentPaths.insert(path, at: 0)
        if snapshot.recentPaths.count > maxRecentCount {
            snapshot.recentPaths = Array(snapshot.recentPaths.prefix(maxRecentCount))
        }
        save(snapshot)
    }

    public func addFavorite(_ url: URL) {
        var snapshot = loadSnapshot()
        let path = normalizedPath(for: url)
        snapshot.favoritePaths.removeAll { $0 == path }
        snapshot.favoritePaths.insert(path, at: 0)
        snapshot.recentPaths.removeAll { $0 == path }
        save(snapshot)
    }

    public func isFavorite(_ url: URL) -> Bool {
        let path = normalizedPath(for: url)
        return loadSnapshot().favoritePaths.contains(path)
    }

    public func removeFavorite(_ url: URL) {
        var snapshot = loadSnapshot()
        let path = normalizedPath(for: url)
        snapshot.favoritePaths.removeAll { $0 == path }
        snapshot.recentPaths.removeAll { $0 == path }
        snapshot.recentPaths.insert(path, at: 0)
        if snapshot.recentPaths.count > maxRecentCount {
            snapshot.recentPaths = Array(snapshot.recentPaths.prefix(maxRecentCount))
        }
        save(snapshot)
    }

    private func loadSnapshot() -> Snapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data)
        else {
            return Snapshot(recentPaths: [], favoritePaths: [])
        }

        return Snapshot(
            recentPaths: deduplicatedExistingPaths(snapshot.recentPaths),
            favoritePaths: deduplicatedExistingPaths(snapshot.favoritePaths)
        )
    }

    private func save(_ snapshot: Snapshot) {
        let cleanSnapshot = Snapshot(
            recentPaths: deduplicatedExistingPaths(snapshot.recentPaths),
            favoritePaths: deduplicatedExistingPaths(snapshot.favoritePaths)
        )
        if let data = try? JSONEncoder().encode(cleanSnapshot) {
            defaults.set(data, forKey: key)
        }
    }

    private func deduplicatedExistingPaths(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for path in paths {
            let normalized = normalizedPath(for: URL(fileURLWithPath: path))
            guard seen.insert(normalized).inserted else { continue }
            result.append(normalized)
        }
        return result
    }

    private func normalizedPath(for url: URL) -> String {
        url.standardizedFileURL.path
    }
}
