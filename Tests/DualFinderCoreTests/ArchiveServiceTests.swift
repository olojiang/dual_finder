import Foundation
import Testing
@testable import DualFinderCore

@Suite("ArchiveService")
struct ArchiveServiceTests {
    @Test("filters compressible and extractable selections")
    func selectionFilters() {
        let zip = URL(fileURLWithPath: "/tmp/a.zip")
        let txt = URL(fileURLWithPath: "/tmp/a.txt")
        let folder = URL(fileURLWithPath: "/tmp/folder")

        #expect(ArchiveService.canCompress([zip, txt]))
        #expect(ArchiveService.compressibleSources(from: [zip, txt]) == [txt])
        #expect(ArchiveService.hasExtractableArchives([zip, txt]))
        #expect(ArchiveService.extractableArchives(from: [zip, folder]) == [zip])
    }

    @Test("compresses a single file to zip")
    func compressSingleFile() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("note.txt")
        try "hello".write(to: source, atomically: true, encoding: .utf8)

        let created = try ArchiveService(logger: CapturingLogger()).compressToZip(sources: [source])

        #expect(created.lastPathComponent == "note.zip")
        #expect(FileManager.default.fileExists(atPath: created.path))

        let extractDir = root.url.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
        try ArchiveService().extract(archives: [created], mode: .currentDirectory)
        #expect(FileManager.default.fileExists(atPath: root.url.appendingPathComponent("note.txt").path))
    }

    @Test("extracts zip to named subfolder")
    func extractToSubfolder() throws {
        let root = try TemporaryDirectory()
        let source = root.url.appendingPathComponent("payload.txt")
        try "payload".write(to: source, atomically: true, encoding: .utf8)
        let archive = try ArchiveService().compressToZip(sources: [source])

        try ArchiveService().extract(archives: [archive], mode: .namedSubfolder)

        let subfolder = root.url.appendingPathComponent("payload", isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: subfolder.path))
        #expect(FileManager.default.fileExists(atPath: subfolder.appendingPathComponent("payload.txt").path))
    }

    @Test("rejects mixed parent directories for compress")
    func mixedParentsRejected() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        let a = left.appendingPathComponent("a.txt")
        let b = right.appendingPathComponent("b.txt")
        try "a".write(to: a, atomically: true, encoding: .utf8)
        try "b".write(to: b, atomically: true, encoding: .utf8)

        #expect(throws: ArchiveError.mixedParentDirectories) {
            try ArchiveService().compressToZip(sources: [a, b])
        }
    }

    @Test("command runner surfaces failures")
    func commandFailure() throws {
        let runner = StubCommandRunner(results: [
            CommandResult(exitCode: 1, stdout: "", stderr: "boom")
        ])
        let root = try TemporaryDirectory()
        let archive = root.url.appendingPathComponent("missing.zip")
        try Data().write(to: archive)

        #expect(throws: ArchiveError.self) {
            try ArchiveService(commandRunner: runner).extract(archives: [archive], mode: .currentDirectory)
        }
    }
}

private final class StubCommandRunner: CommandRunning, @unchecked Sendable {
    private let results: [CommandResult]
    private var index = 0

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult {
        guard index < results.count else {
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        defer { index += 1 }
        return results[index]
    }
}
