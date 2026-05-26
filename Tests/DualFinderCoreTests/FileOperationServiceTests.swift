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
}
