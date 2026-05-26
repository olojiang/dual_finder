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

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }
}
