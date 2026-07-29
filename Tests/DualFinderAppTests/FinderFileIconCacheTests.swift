import AppKit
import Testing
@testable import DualFinderApp

@MainActor
@Suite("Finder file icon cache")
struct FinderFileIconCacheTests {
    @Test("reuses icons for the same standardized file URL")
    func reusesIconsForSameStandardizedURL() {
        var loadCount = 0
        let image = NSImage(size: NSSize(width: 16, height: 16))
        let cache = FinderFileIconCache(loader: { _ in
            loadCount += 1
            return image
        })
        let url = URL(fileURLWithPath: "/tmp/folder/../file.txt")

        let first = cache.icon(for: url)
        let second = cache.icon(for: url.standardizedFileURL)

        #expect(first === image)
        #expect(second === image)
        #expect(loadCount == 1)
    }

    @Test("can clear cached icons")
    func clearsCachedIcons() {
        var loadCount = 0
        let cache = FinderFileIconCache(loader: { _ in
            loadCount += 1
            return NSImage(size: NSSize(width: 16, height: 16))
        })
        let url = URL(fileURLWithPath: "/tmp/file.md")

        _ = cache.icon(for: url)
        cache.removeAllObjects()
        _ = cache.icon(for: url)

        #expect(loadCount == 2)
    }

    @Test("clear resets icon load counter")
    func clearResetsIconLoadCounter() {
        let cache = FinderFileIconCache(loader: { _ in
            NSImage(size: NSSize(width: 16, height: 16))
        })
        let url = URL(fileURLWithPath: "/tmp/file.md")

        _ = cache.icon(for: url)
        #expect(cache.iconLoadCount == 1)
        cache.clear()
        #expect(cache.iconLoadCount == 0)
    }

    @Test("cache holds more than the legacy 200-entry limit")
    func cacheHoldsMoreThanLegacy200Entries() {
        // Regression guard: countLimit was 200, causing thrash on 10000-file
        // directories. With the raised limit, 250 unique URLs must all stay
        // cached (no reload on second access).
        let cache = FinderFileIconCache(loader: { _ in
            NSImage(size: NSSize(width: 16, height: 16))
        })
        let urls = (0..<250).map { URL(fileURLWithPath: "/tmp/bench/file\($0).txt") }

        for url in urls { _ = cache.icon(for: url) }
        let loadsAfterFirstPass = cache.iconLoadCount
        #expect(loadsAfterFirstPass == 250)

        for url in urls { _ = cache.icon(for: url) }
        // If any entry was evicted, iconLoadCount would exceed 250.
        #expect(cache.iconLoadCount == 250)
    }
}
