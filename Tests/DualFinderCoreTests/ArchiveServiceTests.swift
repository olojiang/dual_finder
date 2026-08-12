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

    @Test("repairs GBK ZIP entry names after macOS extraction")
    func repairsLegacyChineseZipEntryNames() throws {
        let root = try TemporaryDirectory()
        let archive = root.url.appendingPathComponent("legacy-gbk.zip")
        try makeLegacyZip(
            at: archive,
            entries: [
                (name: [0xBC, 0xCD, 0xCE, 0xB0, 0xCD, 0xBC, 0xD6, 0xBD, 0xCC, 0xE1, 0xB9, 0xA9, 0x2F], data: []),
                (name: [0xBC, 0xCD, 0xCE, 0xB0, 0xCD, 0xBC, 0xD6, 0xBD, 0xCC, 0xE1, 0xB9, 0xA9, 0x2F, 0xCB, 0xB5, 0xC3, 0xF7, 0x2E, 0x74, 0x78, 0x74], data: Array("payload".utf8))
            ]
        )

        try ArchiveService().extract(archives: [archive], mode: .currentDirectory)

        let repairedFolder = root.url.appendingPathComponent("纪伟图纸提供", isDirectory: true)
        let repairedFile = repairedFolder.appendingPathComponent("说明.txt")
        #expect(FileManager.default.fileExists(atPath: repairedFolder.path))
        #expect(try String(contentsOf: repairedFile, encoding: .utf8) == "payload")
        #expect(!FileManager.default.fileExists(atPath: root.url.appendingPathComponent("ºÕŒ∞Õº÷ΩÃ·π©").path))
    }

    @Test("repairs a legacy Chinese file name without an explicit directory entry")
    func repairsLegacyChineseFileNameWithoutDirectoryEntry() throws {
        let root = try TemporaryDirectory()
        let archive = root.url.appendingPathComponent("legacy-file-name.zip")
        try makeLegacyZip(
            at: archive,
            entries: [
                (name: [0xBD, 0xF8, 0xB2, 0xA9, 0xBB, 0xE1, 0x2F, 0xBD, 0xF8, 0xB2, 0xA9, 0xBB, 0xE1, 0xD7, 0xCA, 0xC1, 0xCF, 0x2E, 0x7A, 0x69, 0x70], data: Array("nested archive".utf8))
            ]
        )

        try ArchiveService().extract(archives: [archive], mode: .currentDirectory)

        let repairedFile = root.url
            .appendingPathComponent("进博会", isDirectory: true)
            .appendingPathComponent("进博会资料.zip")
        #expect(try String(contentsOf: repairedFile, encoding: .utf8) == "nested archive")
    }

    @Test("repairs legacy components beneath a UTF-8 directory")
    func repairsLegacyComponentUnderUTF8Directory() throws {
        let root = try TemporaryDirectory()
        let archive = root.url.appendingPathComponent("mixed-encoding.zip")
        try makeLegacyZip(
            at: archive,
            entries: [
                (name: Array("纪伟图纸提供".utf8) + [0x2F, 0xCB, 0xB5, 0xC3, 0xF7, 0x2E, 0x74, 0x78, 0x74], data: Array("payload".utf8))
            ]
        )

        try ArchiveService().extract(archives: [archive], mode: .currentDirectory)

        let repairedFile = root.url
            .appendingPathComponent("纪伟图纸提供", isDirectory: true)
            .appendingPathComponent("说明.txt")
        #expect(try String(contentsOf: repairedFile, encoding: .utf8) == "payload")
    }

    @Test("uses the ZIP Unicode Path extra field for legacy names")
    func repairsUsingUnicodePathExtraField() throws {
        let root = try TemporaryDirectory()
        let archive = root.url.appendingPathComponent("unicode-path-extra.zip")
        let rawName: [UInt8] = [
            0xBC, 0xCD, 0xCE, 0xB0, 0xCD, 0xBC, 0xD6, 0xBD, 0xCC, 0xE1, 0xB9, 0xA9,
            0x2F, 0xBB, 0xF4, 0xC4, 0xE1, 0xCE, 0xA4, 0xB6, 0xFB, 0x2F,
            0x42, 0x41, 0xCD, 0xBC, 0xD6, 0xBD, 0x20, 0x33, 0x28, 0x31, 0x29, 0x2F,
            0x42, 0x41, 0xCD, 0xBC, 0xD6, 0xBD, 0x2F, 0x46, 0x43, 0x55, 0xD4, 0xAD,
            0xC0, 0xED, 0xCD, 0xBC, 0x2E, 0x70, 0x64, 0x66
        ]
        try makeLegacyZip(
            at: archive,
            entries: [(name: rawName, data: Array("payload".utf8))],
            unicodePaths: [0: Array("纪伟图纸提供/霍尼韦尔/BA图纸 3(1)/BA图纸/FCU原理图.pdf".utf8)]
        )

        try ArchiveService().extract(archives: [archive], mode: .currentDirectory)

        let repairedFile = root.url
            .appendingPathComponent("纪伟图纸提供", isDirectory: true)
            .appendingPathComponent("霍尼韦尔", isDirectory: true)
            .appendingPathComponent("BA图纸 3(1)", isDirectory: true)
            .appendingPathComponent("BA图纸", isDirectory: true)
            .appendingPathComponent("FCU原理图.pdf")
        #expect(try String(contentsOf: repairedFile, encoding: .utf8) == "payload")
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

private func makeLegacyZip(
    at url: URL,
    entries: [(name: [UInt8], data: [UInt8])],
    unicodePaths: [Int: [UInt8]] = [:]
) throws {
    var archive = Data()
    var centralDirectory = Data()
    var localOffsets: [UInt32] = []

    for entry in entries {
        let name = Data(entry.name)
        let data = Data(entry.data)
        let crc = UInt32(zlibCRC32(data))
        localOffsets.append(UInt32(archive.count))
        appendLittleEndian(UInt32(0x04034B50), to: &archive)
        appendLittleEndian(UInt16(20), to: &archive)
        appendLittleEndian(UInt16(0), to: &archive)
        appendLittleEndian(UInt16(0), to: &archive)
        appendLittleEndian(UInt16(0), to: &archive)
        appendLittleEndian(UInt16(0), to: &archive)
        appendLittleEndian(crc, to: &archive)
        appendLittleEndian(UInt32(data.count), to: &archive)
        appendLittleEndian(UInt32(data.count), to: &archive)
        appendLittleEndian(UInt16(name.count), to: &archive)
        appendLittleEndian(UInt16(0), to: &archive)
        archive.append(name)
        archive.append(data)
    }

    for (index, entry) in entries.enumerated() {
        let name = Data(entry.name)
        let data = Data(entry.data)
        let crc = UInt32(zlibCRC32(data))
        let extra = unicodePaths[index].map { unicodePathExtra(rawName: entry.name, path: $0) } ?? Data()
        appendLittleEndian(UInt32(0x02014B50), to: &centralDirectory)
        appendLittleEndian(UInt16(20), to: &centralDirectory)
        appendLittleEndian(UInt16(20), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(crc, to: &centralDirectory)
        appendLittleEndian(UInt32(data.count), to: &centralDirectory)
        appendLittleEndian(UInt32(data.count), to: &centralDirectory)
        appendLittleEndian(UInt16(name.count), to: &centralDirectory)
        appendLittleEndian(UInt16(extra.count), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(UInt16(0), to: &centralDirectory)
        appendLittleEndian(UInt32(entry.name.last == 0x2F ? 0x10 : 0), to: &centralDirectory)
        appendLittleEndian(localOffsets[index], to: &centralDirectory)
        centralDirectory.append(name)
        centralDirectory.append(extra)
    }

    let centralOffset = UInt32(archive.count)
    archive.append(centralDirectory)
    appendLittleEndian(UInt32(0x06054B50), to: &archive)
    appendLittleEndian(UInt16(0), to: &archive)
    appendLittleEndian(UInt16(0), to: &archive)
    appendLittleEndian(UInt16(entries.count), to: &archive)
    appendLittleEndian(UInt16(entries.count), to: &archive)
    appendLittleEndian(UInt32(centralDirectory.count), to: &archive)
    appendLittleEndian(centralOffset, to: &archive)
    appendLittleEndian(UInt16(0), to: &archive)
    try archive.write(to: url)
}

private func unicodePathExtra(rawName: [UInt8], path: [UInt8]) -> Data {
    var extra = Data()
    let payloadLength = 1 + 4 + path.count
    appendLittleEndian(UInt16(0x7075), to: &extra)
    appendLittleEndian(UInt16(payloadLength), to: &extra)
    extra.append(1)
    appendLittleEndian(UInt32(zlibCRC32(Data(rawName))), to: &extra)
    extra.append(contentsOf: path)
    return extra
}

private func appendLittleEndian<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
    var value = value.littleEndian
    withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
}

private func zlibCRC32(_ data: Data) -> UInt32 {
    var crc: UInt32 = 0xFFFF_FFFF
    for byte in data {
        crc ^= UInt32(byte)
        for _ in 0..<8 {
            crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0)
        }
    }
    return crc ^ 0xFFFF_FFFF
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
