import Foundation
import Testing
@testable import DualFinderCore

@Suite("OperationScanCache")
struct OperationScanCacheTests {
    @Test("reuses cached scan plan when folder modification date matches")
    func reusesCachedScanPlanWhenFolderModificationDateMatches() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("scan-cache.json")
        let folder = root.url.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let modifiedAt = Date(timeIntervalSince1970: 500)
        let now = Date(timeIntervalSince1970: 1_000)
        let cache = OperationScanCache(storageURL: cacheURL, dateProvider: { now })
        try cache.setPlan(OperationScanPlan(totalBytes: 42, totalItems: 7), for: folder, modifiedAt: modifiedAt)

        #expect(cache.plan(for: folder, modifiedAt: modifiedAt) == OperationScanPlan(totalBytes: 42, totalItems: 7))
        #expect(cache.plan(for: folder, modifiedAt: Date(timeIntervalSince1970: 600)) == nil)
    }

    @Test("expires cached scan plans after one day")
    func expiresCachedScanPlansAfterOneDay() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("scan-cache.json")
        let folder = root.url.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let modifiedAt = Date(timeIntervalSince1970: 500)
        var now = Date(timeIntervalSince1970: 1_000)
        let cache = OperationScanCache(storageURL: cacheURL, dateProvider: { now })
        try cache.setPlan(OperationScanPlan(totalBytes: 10, totalItems: 2), for: folder, modifiedAt: modifiedAt)
        #expect(cache.plan(for: folder, modifiedAt: modifiedAt) != nil)

        now = Date(timeIntervalSince1970: 1_000 + 86_401)
        #expect(cache.plan(for: folder, modifiedAt: modifiedAt) == nil)
    }
}
