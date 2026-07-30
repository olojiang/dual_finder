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

    @Test("extract aborts remaining archives after cancellation between files")
    func extractCancelsBetweenArchives() throws {
        let root = try TemporaryDirectory()
        let firstArchive = root.url.appendingPathComponent("first.zip")
        let secondArchive = root.url.appendingPathComponent("second.zip")
        try Data().write(to: firstArchive)
        try Data().write(to: secondArchive)

        let cancellation = FileOperationCancellation()
        let runner = CancellingStubRunner(onRun: { cancellation.cancel() })
        let service = ArchiveService(commandRunner: runner)

        #expect(throws: ArchiveError.cancelled) {
            try service.extract(
                archives: [firstArchive, secondArchive],
                mode: .currentDirectory,
                cancellation: cancellation
            )
        }

        #expect(runner.runCount == 1)
    }

    @Test("extract forwards cancellation to a cancellable runner and aborts")
    func extractForwardsCancellationToCancellableRunner() throws {
        let root = try TemporaryDirectory()
        let archive = root.url.appendingPathComponent("first.zip")
        try Data().write(to: archive)

        let cancellation = FileOperationCancellation()
        let runner = CancellableStubRunner(onRun: { cancellation.cancel() })
        let service = ArchiveService(commandRunner: runner)

        #expect(throws: ArchiveError.cancelled) {
            try service.extract(
                archives: [archive],
                mode: .currentDirectory,
                cancellation: cancellation
            )
        }

        #expect(runner.runCount == 1)
        #expect(runner.receivedCancellation != nil)
    }

    @Test("extract reports progress after each archive")
    func extractReportsProgressPerArchive() throws {
        let root = try TemporaryDirectory()
        let archives = (0..<3).map { index in
            root.url.appendingPathComponent("archive-\(index).zip")
        }
        for archive in archives {
            try Data().write(to: archive)
        }

        var reported: [(Int, Int)] = []
        try ArchiveService(commandRunner: StubCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: ""),
            CommandResult(exitCode: 0, stdout: "", stderr: "")
        ])).extract(
            archives: archives,
            mode: .currentDirectory,
            progress: { completed, total in reported.append((completed, total)) }
        )

        #expect(reported.map { "\($0.0)/\($0.1)" } == ["1/3", "2/3", "3/3"])
    }
}

private final class CancellingStubRunner: CommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _runCount = 0
    private let onRun: () -> Void

    init(onRun: @escaping () -> Void) {
        self.onRun = onRun
    }

    var runCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _runCount
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult {
        lock.lock()
        _runCount += 1
        lock.unlock()
        onRun()
        return CommandResult(exitCode: 0, stdout: "", stderr: "")
    }
}

private final class CancellableStubRunner: CancellableCommandRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var _runCount = 0
    private var _receivedCancellation: FileOperationCancellation?
    private let onRun: () -> Void

    init(onRun: @escaping () -> Void) {
        self.onRun = onRun
    }

    var runCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return _runCount
    }

    var receivedCancellation: FileOperationCancellation? {
        lock.lock()
        defer { lock.unlock() }
        return _receivedCancellation
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult {
        CommandResult(exitCode: 0, stdout: "", stderr: "")
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?
    ) throws -> CommandResult {
        lock.lock()
        _runCount += 1
        _receivedCancellation = cancellation
        lock.unlock()
        onRun()
        if cancellation?.isCancelled == true {
            throw FileOperationError.cancelled
        }
        return CommandResult(exitCode: 0, stdout: "", stderr: "")
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
