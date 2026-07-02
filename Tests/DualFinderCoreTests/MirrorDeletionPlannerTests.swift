import Foundation
import Testing
@testable import DualFinderCore

@Suite("MirrorDeletionPlanner")
struct MirrorDeletionPlannerTests {
    @Test("reports extras that exist only on destination")
    func reportsDestinationExtras() throws {
        let root = try TemporaryDirectory()
        let destinationDirectory = root.url.appendingPathComponent("destination", isDirectory: true)
        let sourceFolder = root.url.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = destinationDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try "shared".write(to: sourceFolder.appendingPathComponent("shared.txt"), atomically: true, encoding: .utf8)
        try "extra".write(to: destinationFolder.appendingPathComponent("extra.txt"), atomically: true, encoding: .utf8)

        let extras = try MirrorDeletionPlanner.extrasToDelete(
            sources: [sourceFolder],
            destinationDirectory: destinationDirectory
        )

        #expect(extras.count == 1)
        #expect(extras[0].lastPathComponent == "extra.txt")
    }

    @Test("summarizes deletion byte count")
    func summarizesDeletionByteCount() throws {
        let root = try TemporaryDirectory()
        let destinationDirectory = root.url.appendingPathComponent("destination", isDirectory: true)
        let sourceFolder = root.url.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = destinationDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 2048).write(to: destinationFolder.appendingPathComponent("extra.bin"))

        let summary = try MirrorDeletionPlanner.deletionSummary(
            sources: [sourceFolder],
            destinationDirectory: destinationDirectory
        )

        #expect(summary.itemCount == 1)
        #expect(summary.totalByteCount == 2048)
    }

    @Test("mirror copies missing files and deletes extras")
    func mirrorCopiesMissingFilesAndDeletesExtras() throws {
        let root = try TemporaryDirectory()
        let destinationDirectory = root.url.appendingPathComponent("destination", isDirectory: true)
        let sourceFolder = root.url.appendingPathComponent("source", isDirectory: true)
        let destinationFolder = destinationDirectory.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        let shared = sourceFolder.appendingPathComponent("shared.txt")
        let missing = sourceFolder.appendingPathComponent("missing.txt")
        let sharedDestination = destinationFolder.appendingPathComponent("shared.txt")
        let extraDestination = destinationFolder.appendingPathComponent("extra.txt")
        try "shared".write(to: shared, atomically: true, encoding: .utf8)
        try Data("shared".utf8).write(to: sharedDestination)
        try "missing".write(to: missing, atomically: true, encoding: .utf8)
        try "extra".write(to: extraDestination, atomically: true, encoding: .utf8)
        let sharedDate = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes([.modificationDate: sharedDate], ofItemAtPath: shared.path)
        try FileManager.default.setAttributes([.modificationDate: sharedDate], ofItemAtPath: sharedDestination.path)

        let logger = CapturingLogger()
        try FileOperationService(logger: logger).mirror(
            [sourceFolder],
            to: destinationDirectory,
            conflictResolver: { _ in .overwrite }
        )

        #expect(try String(contentsOf: destinationFolder.appendingPathComponent("missing.txt"), encoding: .utf8) == "missing")
        #expect(try String(contentsOf: destinationFolder.appendingPathComponent("shared.txt"), encoding: .utf8) == "shared")
        #expect(!FileManager.default.fileExists(atPath: extraDestination.path))
        #expect(logger.messages.contains { $0.contains("mirror.completed") })
    }
}
