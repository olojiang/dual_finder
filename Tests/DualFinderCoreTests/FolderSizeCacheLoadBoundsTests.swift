import Foundation
import Testing
@testable import DualFinderCore

@Suite("FolderSizeCache load bounds")
struct FolderSizeCacheLoadBoundsTests {
    @Test("limits in-memory entries when loading an oversized persisted cache")
    func limitsInMemoryEntriesWhenLoadingOversizedCache() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let modifiedAt = Date(timeIntervalSince1970: 500)
        let persisted = FolderSizeCache(storageURL: cacheURL, maxEntries: 5)

        for index in 0..<5 {
            try persisted.setSize(
                Int64(index),
                for: root.url.appendingPathComponent("folder-\(index)"),
                modifiedAt: modifiedAt
            )
        }
        try persisted.flush()

        let reloaded = FolderSizeCache(storageURL: cacheURL, maxEntries: 3)

        #expect(reloaded.entryCount == 3)
    }
}
