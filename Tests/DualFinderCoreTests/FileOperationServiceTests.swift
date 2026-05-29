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

    @Test("move skip conflict keeps original source")
    func moveSkipConflictKeepsOriginalSource() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "existing".write(to: destination.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        try FileOperationService(logger: CapturingLogger()).move(
            [source],
            to: destination,
            conflictResolver: { _ in .skip }
        )

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try String(contentsOf: destination.appendingPathComponent("source.txt"), encoding: .utf8) == "existing")
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

    @Test("copies files with overwrite conflict resolution")
    func copiesWithOverwriteConflictResolution() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "existing".write(to: destination.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        try FileOperationService(logger: CapturingLogger()).copy(
            [source],
            to: destination,
            conflictResolver: { _ in .overwrite }
        )

        #expect(try String(contentsOf: destination.appendingPathComponent("source.txt"), encoding: .utf8) == "new")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source 2.txt").path))
    }

    @Test("rejects overwrite when source and destination are the same file")
    func rejectsOverwriteWhenSourceAndDestinationAreSameFile() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        try "payload".write(to: source, atomically: true, encoding: .utf8)

        #expect(throws: FileOperationError.invalidDestination) {
            try FileOperationService(logger: CapturingLogger()).copy(
                [source],
                to: root.url,
                conflictResolver: { _ in .overwrite }
            )
        }

        #expect(try String(contentsOf: source, encoding: .utf8) == "payload")
    }

    @Test("rejects copying a folder into one of its children")
    func rejectsCopyingFolderIntoChild() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source", isDirectory: true)
        let child = source.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "payload".write(to: source.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        #expect(throws: FileOperationError.invalidDestination) {
            try FileOperationService(logger: CapturingLogger()).copy([source], to: child)
        }

        #expect(!FileManager.default.fileExists(atPath: child.appendingPathComponent("source").path))
    }

    @Test("rejects moving a folder into one of its children")
    func rejectsMovingFolderIntoChild() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source", isDirectory: true)
        let child = source.appendingPathComponent("child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try "payload".write(to: source.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)

        #expect(throws: FileOperationError.invalidDestination) {
            try FileOperationService(logger: CapturingLogger()).move([source], to: child)
        }

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(!FileManager.default.fileExists(atPath: child.appendingPathComponent("source").path))
    }

    @Test("skips files with skip conflict resolution")
    func skipsConflictResolution() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "existing".write(to: destination.appendingPathComponent("source.txt"), atomically: true, encoding: .utf8)

        try FileOperationService(logger: CapturingLogger()).copy(
            [source],
            to: destination,
            conflictResolver: { _ in .skip }
        )

        #expect(try String(contentsOf: destination.appendingPathComponent("source.txt"), encoding: .utf8) == "existing")
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source 2.txt").path))
    }

    @Test("reports copy progress")
    func reportsCopyProgress() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.bin")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 7, count: 3 * 1024 * 1024).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var progressEvents: [FileOperationProgress] = []

        try FileOperationService(logger: CapturingLogger()).copy([source], to: destination, progress: { progress in
            progressEvents.append(progress)
        })

        #expect(progressEvents.count >= 2)
        #expect(progressEvents.last?.completedBytes == Int64(3 * 1024 * 1024))
        #expect(progressEvents.last?.completedItems == 1)
    }

    @Test("returns standardized created folder URL")
    func returnsStandardizedCreatedFolderURL() throws {
        let root = try TemporaryDirectory()

        let created = try FileOperationService(logger: CapturingLogger()).createFolder(named: "New Folder", in: root.url)
        let listed = try #require(FileSystemService().contents(of: root.url).first)

        #expect(created == listed.url)
    }

    @Test("creates empty files with unique names")
    func createsEmptyFilesWithUniqueNames() throws {
        let root = try TemporaryDirectory()
        try "existing".write(to: root.url.appendingPathComponent("New File.txt"), atomically: true, encoding: .utf8)
        let logger = CapturingLogger()

        let created = try FileOperationService(logger: logger).createEmptyFile(named: "New File.txt", in: root.url)

        #expect(created.lastPathComponent == "New File 2.txt")
        #expect(FileManager.default.fileExists(atPath: created.path))
        #expect(try Data(contentsOf: created).isEmpty)
        #expect(logger.messages.contains { $0.contains("file.created") })
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
