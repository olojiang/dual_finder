import Foundation
import Testing
@testable import DualFinderCore

@Suite("FolderSizeCache")
struct FolderSizeCacheTests {
    @Test("caches and retrieves folder size by path and modification date")
    func cachesAndRetrievesSize() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL)
        let folder = root.url.appendingPathComponent("Folder")
        let date = Date(timeIntervalSince1970: 500)

        try cache.setSize(42, for: folder, modifiedAt: date)

        #expect(cache.size(for: folder, modifiedAt: date) == 42)
    }

    @Test("returns nil when modification date differs")
    func invalidatesOnModifiedDateChange() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL)
        let folder = root.url.appendingPathComponent("Folder")
        try cache.setSize(42, for: folder, modifiedAt: Date(timeIntervalSince1970: 500))

        #expect(cache.size(for: folder, modifiedAt: Date(timeIntervalSince1970: 600)) == nil)
    }

    @Test("trims to max entries on insertion")
    func trimsToMaxEntries() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL, maxEntries: 3)
        let date = Date(timeIntervalSince1970: 500)

        for index in 0..<5 {
            let folder = root.url.appendingPathComponent("folder-\(index)")
            try cache.setSize(Int64(index), for: folder, modifiedAt: date)
        }

        #expect(cache.entryCount == 3)
        // oldest two should be evicted
        #expect(cache.size(for: root.url.appendingPathComponent("folder-0"), modifiedAt: date) == nil)
        #expect(cache.size(for: root.url.appendingPathComponent("folder-1"), modifiedAt: date) == nil)
        // newest three should remain
        #expect(cache.size(for: root.url.appendingPathComponent("folder-2"), modifiedAt: date) == 2)
        #expect(cache.size(for: root.url.appendingPathComponent("folder-3"), modifiedAt: date) == 3)
        #expect(cache.size(for: root.url.appendingPathComponent("folder-4"), modifiedAt: date) == 4)
    }

    @Test("accessing an entry refreshes its eviction priority")
    func accessRefreshesEvictionPriority() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL, maxEntries: 3)
        let date = Date(timeIntervalSince1970: 500)

        for index in 0..<3 {
            let folder = root.url.appendingPathComponent("folder-\(index)")
            try cache.setSize(Int64(index), for: folder, modifiedAt: date)
        }
        // touch oldest entry to make it most-recently-used
        _ = cache.size(for: root.url.appendingPathComponent("folder-0"), modifiedAt: date)
        // insert one more — should evict folder-1 (now least recently used)
        try cache.setSize(99, for: root.url.appendingPathComponent("folder-3"), modifiedAt: date)

        #expect(cache.entryCount == 3)
        #expect(cache.size(for: root.url.appendingPathComponent("folder-0"), modifiedAt: date) == 0)
        #expect(cache.size(for: root.url.appendingPathComponent("folder-1"), modifiedAt: date) == nil)
    }

    @Test("persists entries to disk and reloads")
    func persistsAndReloads() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let folder = root.url.appendingPathComponent("Folder")
        let date = Date(timeIntervalSince1970: 500)

        let cache = FolderSizeCache(storageURL: cacheURL)
        try cache.setSize(42, for: folder, modifiedAt: date)
        try cache.flush()

        let reloaded = FolderSizeCache(storageURL: cacheURL)
        #expect(reloaded.size(for: folder, modifiedAt: date) == 42)
    }

    @Test("debounces disk writes — in-memory reads work before flush")
    func inMemoryReadsWorkBeforeFlush() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL, debounceInterval: 60)
        let date = Date(timeIntervalSince1970: 500)

        for index in 0..<5 {
            let folder = root.url.appendingPathComponent("folder-\(index)")
            try cache.setSize(Int64(index), for: folder, modifiedAt: date)
        }

        // In-memory reads should work immediately
        #expect(cache.size(for: root.url.appendingPathComponent("folder-3"), modifiedAt: date) == 3)
        // Disk file should not yet contain the entries (debounce interval is 60s)
        let reloaded = FolderSizeCache(storageURL: cacheURL, debounceInterval: 60)
        #expect(reloaded.size(for: root.url.appendingPathComponent("folder-3"), modifiedAt: date) == nil)
    }

    @Test("flush writes all pending entries to disk")
    func flushWritesAllPendingEntries() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL, debounceInterval: 60)
        let date = Date(timeIntervalSince1970: 500)

        for index in 0..<5 {
            let folder = root.url.appendingPathComponent("folder-\(index)")
            try cache.setSize(Int64(index), for: folder, modifiedAt: date)
        }

        try cache.flush()

        let reloaded = FolderSizeCache(storageURL: cacheURL, debounceInterval: 60)
        for index in 0..<5 {
            let folder = root.url.appendingPathComponent("folder-\(index)")
            #expect(reloaded.size(for: folder, modifiedAt: date) == Int64(index))
        }
    }

    @Test("debounce timer eventually writes to disk")
    func debounceTimerEventuallyWrites() async throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let cache = FolderSizeCache(storageURL: cacheURL, debounceInterval: 0.1)
        let date = Date(timeIntervalSince1970: 500)

        try cache.setSize(42, for: root.url.appendingPathComponent("Folder"), modifiedAt: date)

        // Wait for debounce timer to fire
        try await Task.sleep(nanoseconds: 300_000_000)

        let reloaded = FolderSizeCache(storageURL: cacheURL, debounceInterval: 60)
        #expect(reloaded.size(for: root.url.appendingPathComponent("Folder"), modifiedAt: date) == 42)
    }
}
