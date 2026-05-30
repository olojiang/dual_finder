import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileSystemService")
struct FileSystemServiceTests {
    @Test("lists directory entries with folders first and default modified date descending sort")
    func listsDirectoryEntries() throws {
        let root = try TemporaryDirectory()
        let beta = root.url.appendingPathComponent("Beta")
        let alpha = root.url.appendingPathComponent("Alpha")
        try FileManager.default.createDirectory(at: beta, withIntermediateDirectories: true)
        try "file".write(to: root.url.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: alpha, withIntermediateDirectories: true)
        try setModificationDate(Date(timeIntervalSince1970: 100), for: beta)
        try setModificationDate(Date(timeIntervalSince1970: 200), for: alpha)

        let items = try FileSystemService().contents(of: root.url)

        #expect(items.map(\.name) == ["Alpha", "Beta", "alpha.txt"])
        #expect(items[0].kind == .folder)
        #expect(items[2].kind == .file)
    }

    @Test("standardizes listed item URLs")
    func standardizesListedItemURLs() throws {
        let root = try TemporaryDirectory()
        let folder = root.url.appendingPathComponent("New Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let item = try #require(FileSystemService().contents(of: root.url).first)

        #expect(item.url == folder.standardizedFileURL)
        #expect(item.id == item.url)
    }

    @Test("sorts by size in both directions")
    func sortsBySize() throws {
        let root = try TemporaryDirectory()
        try "small".write(to: root.url.appendingPathComponent("small.txt"), atomically: true, encoding: .utf8)
        try "larger file".write(to: root.url.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)

        let ascending = try FileSystemService().contents(
            of: root.url,
            sortRule: FileSortRule(field: .size, direction: .ascending)
        )
        let descending = try FileSystemService().contents(
            of: root.url,
            sortRule: FileSortRule(field: .size, direction: .descending)
        )

        #expect(ascending.map(\.name) == ["small.txt", "large.txt"])
        #expect(descending.map(\.name) == ["large.txt", "small.txt"])
    }

    @Test("sorts by type and falls back to names")
    func sortsByTypeAndFallsBackToNames() throws {
        let root = try TemporaryDirectory()
        try "text".write(to: root.url.appendingPathComponent("beta.txt"), atomically: true, encoding: .utf8)
        try "markdown".write(to: root.url.appendingPathComponent("alpha.md"), atomically: true, encoding: .utf8)
        try "more text".write(to: root.url.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)

        let items = try FileSystemService().contents(
            of: root.url,
            sortRule: FileSortRule(field: .type, direction: .ascending)
        )

        #expect(items.map(\.name) == ["alpha.md", "alpha.txt", "beta.txt"])
    }

    @Test("hides dot files unless hidden files are included")
    func hidesDotFilesUnlessIncluded() throws {
        let root = try TemporaryDirectory()
        try "visible".write(to: root.url.appendingPathComponent("visible.txt"), atomically: true, encoding: .utf8)
        try "hidden".write(to: root.url.appendingPathComponent(".hidden.txt"), atomically: true, encoding: .utf8)

        let visibleOnly = try FileSystemService().contents(of: root.url)
        let includingHidden = try FileSystemService().contents(of: root.url, includeHidden: true)

        #expect(visibleOnly.map(\.name) == ["visible.txt"])
        #expect(includingHidden.map(\.name).contains(".hidden.txt"))
    }

    @Test("returns nil parent for filesystem root")
    func returnsNilParentForFilesystemRoot() {
        let service = FileSystemService()

        #expect(service.parent(of: URL(fileURLWithPath: "/")) == nil)
        #expect(service.parent(of: URL(fileURLWithPath: "/tmp/example")) == URL(fileURLWithPath: "/tmp"))
    }

    @Test("uses valid cached folder sizes and invalidates changed modification dates")
    func usesFolderSizeCache() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let folder = root.url.appendingPathComponent("Folder")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "contents".write(to: folder.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        let cache = FolderSizeCache(storageURL: cacheURL)
        let originalDate = Date(timeIntervalSince1970: 300)
        let changedDate = Date(timeIntervalSince1970: 400)
        try cache.setSize(42, for: folder, modifiedAt: originalDate)
        try setModificationDate(originalDate, for: folder)

        var items = try FileSystemService().contents(of: root.url, folderSizeCache: cache)
        #expect(items.first?.size == 42)

        try setModificationDate(changedDate, for: folder)
        items = try FileSystemService().contents(of: root.url, folderSizeCache: cache)
        #expect(items.first?.size == nil)
    }

    @Test("computes folder sizes while ignoring symbolic links")
    func computesFolderSizeIgnoringSymbolicLinks() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("cache.json")
        let folder = root.url.appendingPathComponent("Folder")
        let nested = folder.appendingPathComponent("Nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 5).write(to: folder.appendingPathComponent("a.bin"))
        try Data(repeating: 2, count: 7).write(to: nested.appendingPathComponent("b.bin"))
        try FileManager.default.createSymbolicLink(
            at: folder.appendingPathComponent("linked.bin"),
            withDestinationURL: nested.appendingPathComponent("b.bin")
        )
        let cache = FolderSizeCache(storageURL: cacheURL)

        let first = try FileSystemService().calculateFolderSize(at: folder, cache: cache)
        let second = try FileSystemService().calculateFolderSize(at: folder, cache: cache)

        #expect(first == .computed(12))
        #expect(second == .cached(12))
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
