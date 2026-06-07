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
}
