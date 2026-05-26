import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileSystemService")
struct FileSystemServiceTests {
    @Test("lists directory entries with folders first and names sorted")
    func listsDirectoryEntries() throws {
        let root = try TemporaryDirectory()
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("Beta"), withIntermediateDirectories: true)
        try "file".write(to: root.url.appendingPathComponent("alpha.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.url.appendingPathComponent("Alpha"), withIntermediateDirectories: true)

        let items = try FileSystemService().contents(of: root.url)

        #expect(items.map(\.name) == ["Alpha", "Beta", "alpha.txt"])
        #expect(items[0].kind == .folder)
        #expect(items[2].kind == .file)
    }
}
