import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileOperationService")
struct FileOperationServiceTests {
    @Test("copies files into destination directory")
    func copiesFiles() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let logger = CapturingLogger()

        try FileOperationService(logger: logger).copy([source], to: destination)

        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("source.txt").path))
        #expect(logger.messages.contains { $0.contains("copy.completed") })
    }

    @Test("moves files into destination directory")
    func movesFiles() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let logger = CapturingLogger()

        try FileOperationService(logger: logger).move([source], to: destination)

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("source.txt").path))
        #expect(logger.messages.contains { $0.contains("move.completed") })
    }

    @Test("copies files to a unique destination without overwriting existing files")
    func copiesToUniqueDestination() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "existing".write(to: destination.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        try FileOperationService(logger: CapturingLogger()).copy([source], to: destination)

        let original = try String(contentsOf: destination.appendingPathComponent("source.txt"), encoding: .utf8)
        let copied = try String(contentsOf: destination.appendingPathComponent("source 2.txt"), encoding: .utf8)
        #expect(original == "existing")
        #expect(copied == "new")
    }

    @Test("returns standardized created folder URL")
    func returnsStandardizedCreatedFolderURL() throws {
        let root = try TemporaryDirectory()

        let created = try FileOperationService(logger: CapturingLogger()).createFolder(named: "New Folder", in: root.url)
        let listed = try #require(FileSystemService().contents(of: root.url).first)

        #expect(created == listed.url)
    }

    @Test("renames files in place")
    func renamesFilesInPlace() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("old.txt")
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        let logger = CapturingLogger()

        let renamed = try FileOperationService(logger: logger).rename(source, to: "new.txt")

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("new.txt").path))
        #expect(renamed.lastPathComponent == "new.txt")
        #expect(logger.messages.contains { $0.contains("rename.completed") })
    }

    @Test("rejects empty rename names")
    func rejectsEmptyRenameNames() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        try "payload".write(to: source, atomically: true, encoding: .utf8)

        #expect(throws: FileOperationError.emptyName) {
            try FileOperationService(logger: CapturingLogger()).rename(source, to: "   ")
        }
        #expect(FileManager.default.fileExists(atPath: source.path))
    }

    @Test("batch renames through temporary names so items can swap")
    func batchRenamesSwappingItems() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("first.txt")
        let second = root.url.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let results = try FileOperationService(logger: CapturingLogger()).batchRename([
            BatchRenameOperation(sourceURL: first, newName: "second.txt"),
            BatchRenameOperation(sourceURL: second, newName: "first.txt")
        ])

        #expect(results.map(\.lastPathComponent) == ["second.txt", "first.txt"])
        #expect(try String(contentsOf: root.url.appendingPathComponent("first.txt"), encoding: .utf8) == "two")
        #expect(try String(contentsOf: root.url.appendingPathComponent("second.txt"), encoding: .utf8) == "one")
    }

    @Test("empties trash directory contents")
    func emptiesTrashDirectoryContents() throws {
        let root = try TemporaryDirectory()
        let trash = root.url.appendingPathComponent("Trash", isDirectory: true)
        let file = trash.appendingPathComponent("discard.txt")
        let folder = trash.appendingPathComponent("discard-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "discard".write(to: file, atomically: true, encoding: .utf8)
        let logger = CapturingLogger()

        let removedCount = try FileOperationService(logger: logger).emptyTrash(at: trash)

        #expect(removedCount == 2)
        #expect(FileManager.default.fileExists(atPath: trash.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: trash.path).isEmpty)
        #expect(logger.messages.contains { $0.contains("trash.empty.completed") })
    }

    #if os(macOS)
    @Test("moves files to the macOS Trash")
    func movesFilesToTrash() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("discard.txt")
        try "discard".write(to: source, atomically: true, encoding: .utf8)
        let logger = CapturingLogger()

        try FileOperationService(logger: logger).trash([source])

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(logger.messages.contains { $0.contains("trash.completed") })
    }
    #endif
}
