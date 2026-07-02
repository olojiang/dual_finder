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
        #expect(logger.messages.contains { $0.contains("move.item.renamed") })
        #expect(!logger.messages.contains { $0.contains("copy.item.completed") })
    }

    @Test("move without destination conflict does not ask resolver")
    func moveWithoutDestinationConflictDoesNotAskResolver() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var resolverWasCalled = false

        try FileOperationService(logger: CapturingLogger()).move(
            [source],
            to: destination,
            conflictResolver: { _ in
                resolverWasCalled = true
                return .skip
            }
        )

        #expect(!resolverWasCalled)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: destination.appendingPathComponent("source.txt").path))
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

    @Test("merges same-named folders instead of treating them as a top-level conflict")
    func mergesSameNamedFolders() throws {
        let root = try TemporaryDirectory()
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        let sourceFolder = root.url.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = destination.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try "only-source".write(to: sourceFolder.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        try "only-destination".write(to: destinationFolder.appendingPathComponent("existing.txt"), atomically: true, encoding: .utf8)
        let logger = CapturingLogger()

        try FileOperationService(logger: logger).copy([sourceFolder], to: destination)

        #expect(FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("new.txt").path))
        #expect(FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("existing.txt").path))
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source 2", isDirectory: true).path))
        #expect(logger.messages.contains { $0.contains("conflict.merge-directories") })
    }

    @Test("sync mode skips identical files and copies missing files")
    func syncModeSkipsIdenticalFiles() throws {
        let root = try TemporaryDirectory()
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        let sourceFolder = root.url.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = destination.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let shared = sourceFolder.appendingPathComponent("same.txt")
        let sourceOnly = sourceFolder.appendingPathComponent("missing.txt")
        let sharedDestination = destinationFolder.appendingPathComponent("same.txt")
        try "shared".write(to: shared, atomically: true, encoding: .utf8)
        try Data("shared".utf8).write(to: sharedDestination)
        try "missing".write(to: sourceOnly, atomically: true, encoding: .utf8)
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: sharedDate], ofItemAtPath: shared.path)
        try FileManager.default.setAttributes([.modificationDate: sharedDate], ofItemAtPath: sharedDestination.path)

        let logger = CapturingLogger()
        try FileOperationService(logger: logger).copy(
            [sourceFolder],
            to: destination,
            options: FileOperationOptions(syncMode: true),
            conflictResolver: { _ in .overwrite }
        )

        #expect(try String(contentsOf: destinationFolder.appendingPathComponent("missing.txt"), encoding: .utf8) == "missing")
        #expect(try String(contentsOf: destinationFolder.appendingPathComponent("same.txt"), encoding: .utf8) == "shared")
        #expect(logger.messages.contains { $0.contains("sync.skip-identical") })
    }

    @Test("move into existing folder keeps source when directories are merged")
    func moveIntoExistingFolderKeepsSource() throws {
        let root = try TemporaryDirectory()
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        let sourceFolder = root.url.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = destination.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try "payload".write(to: sourceFolder.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        let logger = CapturingLogger()

        try FileOperationService(logger: logger).move([sourceFolder], to: destination)

        #expect(FileManager.default.fileExists(atPath: sourceFolder.path))
        #expect(FileManager.default.fileExists(atPath: destinationFolder.appendingPathComponent("new.txt").path))
        #expect(logger.messages.contains { $0.contains("move.merge.source-kept") })
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

    @Test("largerWins resolution overwrites when source is larger than destination")
    func largerWinsOverwritesWhenSourceLarger() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 1, count: 1024).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 256).write(to: destination.appendingPathComponent("source.txt"))

        try FileOperationService(logger: CapturingLogger()).copy(
            [source],
            to: destination,
            conflictResolver: { _ in .largerWins }
        )

        let copy = destination.appendingPathComponent("source.txt")
        #expect(try Data(contentsOf: copy).count == 1024)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source 2.txt").path))
    }

    @Test("largerWins resolution overwrites when source equals destination size")
    func largerWinsOverwritesWhenSourceEqual() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 1, count: 512).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 512).write(to: destination.appendingPathComponent("source.txt"))

        try FileOperationService(logger: CapturingLogger()).copy(
            [source],
            to: destination,
            conflictResolver: { _ in .largerWins }
        )

        #expect(try Data(contentsOf: destination.appendingPathComponent("source.txt")).count == 512)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source 2.txt").path))
    }

    @Test("largerWins resolution skips when destination is larger than source")
    func largerWinsSkipsWhenDestinationLarger() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 1, count: 256).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 1024).write(to: destination.appendingPathComponent("source.txt"))

        try FileOperationService(logger: CapturingLogger()).copy(
            [source],
            to: destination,
            conflictResolver: { _ in .largerWins }
        )

        let existing = destination.appendingPathComponent("source.txt")
        #expect(try Data(contentsOf: existing).count == 1024)
        #expect(!FileManager.default.fileExists(atPath: destination.appendingPathComponent("source 2.txt").path))
    }

    @Test("largerWins resolution moves source when it is larger than destination")
    func largerWinsMovesWhenSourceLarger() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 1, count: 1024).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 256).write(to: destination.appendingPathComponent("source.txt"))

        try FileOperationService(logger: CapturingLogger()).move(
            [source],
            to: destination,
            conflictResolver: { _ in .largerWins }
        )

        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("source.txt")).count == 1024)
    }

    @Test("largerWins resolution keeps source in place when destination is larger")
    func largerWinsKeepsSourceWhenDestinationLarger() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 1, count: 256).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 1024).write(to: destination.appendingPathComponent("source.txt"))

        try FileOperationService(logger: CapturingLogger()).move(
            [source],
            to: destination,
            conflictResolver: { _ in .largerWins }
        )

        #expect(FileManager.default.fileExists(atPath: source.path))
        #expect(try Data(contentsOf: destination.appendingPathComponent("source.txt")).count == 1024)
    }

    @Test("largerWinsResolution returns overwrite when source is larger or equal")
    func largerWinsResolutionStaticHelperComparesSizes() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try Data(repeating: 1, count: 1024).write(to: source)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data(repeating: 2, count: 256).write(to: destination.appendingPathComponent("source.txt"))

        let largerConflict = FileOperationConflict(
            source: source,
            destination: destination.appendingPathComponent("source.txt")
        )
        #expect(FileOperationService.largerWinsResolution(for: largerConflict) == .overwrite)

        try Data(repeating: 3, count: 2048).write(to: destination.appendingPathComponent("source.txt"))
        let smallerConflict = FileOperationConflict(
            source: source,
            destination: destination.appendingPathComponent("source.txt")
        )
        #expect(FileOperationService.largerWinsResolution(for: smallerConflict) == .skip)

        try Data(repeating: 4, count: 1024).write(to: destination.appendingPathComponent("source.txt"))
        let equalConflict = FileOperationConflict(
            source: source,
            destination: destination.appendingPathComponent("source.txt")
        )
        #expect(FileOperationService.largerWinsResolution(for: equalConflict) == .overwrite)
    }

    @Test("largerWinsResolution falls back to skip when sizes cannot be read")
    func largerWinsResolutionFallsBackToSkipWhenSizesUnknown() {
        let missing = URL(fileURLWithPath: "/tmp/dual-finder-larger-wins-missing-\(UUID().uuidString).txt")
        let conflict = FileOperationConflict(source: missing, destination: missing)

        #expect(FileOperationService.largerWinsResolution(for: conflict) == .skip)
    }

    @Test("largerWinsResolution skips when either side is a directory")
    func largerWinsResolutionSkipsWhenEitherSideIsDirectory() throws {
        let root = try TemporaryDirectory()
        let sourceDir = root.url.appendingPathComponent("source-dir", isDirectory: true)
        let destinationDir = root.url.appendingPathComponent("destination-dir", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 64).write(to: sourceDir.appendingPathComponent("file.txt"))
        try Data(repeating: 2, count: 32).write(to: destinationDir.appendingPathComponent("file.txt"))

        let bothDirectories = FileOperationConflict(source: sourceDir, destination: destinationDir)
        let sourceFile = FileOperationConflict(
            source: sourceDir.appendingPathComponent("file.txt"),
            destination: destinationDir
        )
        let destinationFile = FileOperationConflict(
            source: sourceDir,
            destination: destinationDir.appendingPathComponent("file.txt")
        )

        #expect(FileOperationService.largerWinsResolution(for: bothDirectories) == .skip)
        #expect(FileOperationService.largerWinsResolution(for: sourceFile) == .skip)
        #expect(FileOperationService.largerWinsResolution(for: destinationFile) == .skip)
    }

    @Test("largerWinsResolution returns overwrite for two equal-sized files")
    func largerWinsResolutionOverwritesForEqualSizes() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("source.txt")
        let destination = root.url.appendingPathComponent("destination.txt")
        try Data(repeating: 9, count: 128).write(to: source)
        try Data(repeating: 8, count: 128).write(to: destination)

        let conflict = FileOperationConflict(source: source, destination: destination)
        #expect(FileOperationService.largerWinsResolution(for: conflict) == .overwrite)
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

    @Test("renaming folders returns the same URL identity as directory listings")
    func renamingFoldersReturnsListedURLIdentity() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("Old Folder", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)

        let renamed = try FileOperationService(logger: CapturingLogger()).rename(source, to: "New Folder")
        let listed = try #require(FileSystemService().contents(of: root.url).first { $0.name == "New Folder" })

        #expect(renamed == listed.url)
        #expect(renamed.absoluteString == listed.url.absoluteString)
        #expect(listed.isDirectoryLike)
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

    @Test("merges files in source order with line breaks")
    func mergesFilesInSourceOrder() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("first.txt")
        let second = root.url.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two\n".write(to: second, atomically: true, encoding: .utf8)

        let merged = try FileOperationService(logger: CapturingLogger()).mergeFiles(
            [first, second],
            named: "merged.txt",
            in: root.url
        )

        #expect(merged.lastPathComponent == "merged.txt")
        #expect(try String(contentsOf: merged, encoding: .utf8) == "one\ntwo\n")
    }

    @Test("merging files creates a unique destination")
    func mergingFilesCreatesUniqueDestination() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("first.txt")
        let second = root.url.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)
        try "existing".write(to: root.url.appendingPathComponent("merged.txt"), atomically: true, encoding: .utf8)

        let merged = try FileOperationService(logger: CapturingLogger()).mergeFiles(
            [first, second],
            named: "merged.txt",
            in: root.url
        )

        #expect(merged.lastPathComponent == "merged 2.txt")
        #expect(try String(contentsOf: merged, encoding: .utf8) == "one\ntwo")
        #expect(try String(contentsOf: root.url.appendingPathComponent("merged.txt"), encoding: .utf8) == "existing")
    }

    @Test("merging files can move originals to trash")
    func mergingFilesCanTrashOriginals() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("first.txt")
        let second = root.url.appendingPathComponent("second.txt")
        try "one".write(to: first, atomically: true, encoding: .utf8)
        try "two".write(to: second, atomically: true, encoding: .utf8)

        let merged = try FileOperationService(logger: CapturingLogger()).mergeFiles(
            [first, second],
            named: "merged.txt",
            in: root.url,
            trashSourcesAfterMerge: true
        )

        #expect(FileManager.default.fileExists(atPath: merged.path))
        #expect(!FileManager.default.fileExists(atPath: first.path))
        #expect(!FileManager.default.fileExists(atPath: second.path))
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

    @Test("summarizes trash contents before emptying")
    func summarizesTrashContentsBeforeEmptying() throws {
        let root = try TemporaryDirectory()
        let trash = root.url.appendingPathComponent("Trash", isDirectory: true)
        let file = trash.appendingPathComponent("discard.txt")
        let folder = trash.appendingPathComponent("discard-folder", isDirectory: true)
        let nested = folder.appendingPathComponent("nested.txt")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try "discard".write(to: file, atomically: true, encoding: .utf8)
        try "nested".write(to: nested, atomically: true, encoding: .utf8)

        let summary = try FileOperationService(logger: CapturingLogger()).trashContentsSummary(at: trash)

        #expect(summary.topLevelItemCount == 2)
        #expect(summary.containedItemCount == 3)
        #expect(summary.totalByteCount == 13)
        #expect(!summary.isEmpty)
    }

    @Test("ignores trash metadata files when summarizing and emptying")
    func ignoresTrashMetadataFilesWhenSummarizingAndEmptying() throws {
        let root = try TemporaryDirectory()
        let trash = root.url.appendingPathComponent("Trash", isDirectory: true)
        let file = trash.appendingPathComponent("discard.txt")
        let metadata = trash.appendingPathComponent(".DS_Store")
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        try "discard".write(to: file, atomically: true, encoding: .utf8)
        try "metadata".write(to: metadata, atomically: true, encoding: .utf8)

        let service = FileOperationService(logger: CapturingLogger())
        let summary = try service.trashContentsSummary(at: trash)
        let removedCount = try service.emptyTrash(at: trash)

        #expect(summary.topLevelItemCount == 1)
        #expect(summary.containedItemCount == 1)
        #expect(summary.totalByteCount == 7)
        #expect(removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: metadata.path))
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
