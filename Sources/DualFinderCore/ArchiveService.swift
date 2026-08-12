import Foundation
import CoreFoundation

public enum ArchiveExtractionMode: Sendable, Equatable {
    case currentDirectory
    case namedSubfolder
}

public enum ArchiveError: LocalizedError, Equatable {
    case noSources
    case noArchives
    case nothingToCompress
    case mixedParentDirectories
    case unsupportedFormat(ArchiveFormat)
    case toolNotFound(String)
    case commandFailed(command: String, exitCode: Int32, detail: String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .noSources:
            "No items were selected."
        case .noArchives:
            "No supported archive files were selected."
        case .nothingToCompress:
            "Nothing to compress in the current selection."
        case .mixedParentDirectories:
            "Selected items must be in the same folder to compress together."
        case .unsupportedFormat(let format):
            "Unsupported archive format: \(format.rawValue)."
        case .toolNotFound(let tool):
            "Required tool not found: \(tool). Install 7-Zip (7z) or unar for \(tool) archives."
        case .commandFailed(let command, let exitCode, let detail):
            "Command failed (\(exitCode)): \(command). \(detail)"
        case .cancelled:
            "Archive operation cancelled."
        }
    }
}

public struct ArchiveService {
    private let fileManager: FileManager
    private let commandRunner: any CommandRunning
    private let logger: AppLogging?

    public init(
        fileManager: FileManager = .default,
        commandRunner: any CommandRunning = ProcessCommandRunner(),
        logger: AppLogging? = nil
    ) {
        self.fileManager = fileManager
        self.commandRunner = commandRunner
        self.logger = logger
    }

    public static func compressibleSources(from urls: [URL]) -> [URL] {
        urls.filter { !ArchiveFormatDetector.isExtractable($0) }
    }

    public static func extractableArchives(from urls: [URL]) -> [URL] {
        urls.filter { ArchiveFormatDetector.isExtractable($0) }
    }

    public static func canCompress(_ urls: [URL]) -> Bool {
        !compressibleSources(from: urls).isEmpty
    }

    public static func hasExtractableArchives(_ urls: [URL]) -> Bool {
        !extractableArchives(from: urls).isEmpty
    }

    public func compressToZip(
        sources: [URL],
        cancellation: FileOperationCancellation? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) throws -> URL {
        let items = Self.compressibleSources(from: sources)
        guard !items.isEmpty else { throw ArchiveError.nothingToCompress }
        try throwIfCancelled(cancellation)

        let parentDirectories = Set(items.map { $0.deletingLastPathComponent().standardizedFileURL })
        guard parentDirectories.count == 1, let parentDirectory = parentDirectories.first else {
            throw ArchiveError.mixedParentDirectories
        }

        let archiveBaseName = zipBaseName(for: items)
        let destination = uniqueArchiveURL(named: "\(archiveBaseName).zip", in: parentDirectory)

        logger?.info("archive", "compress.started", metadata: [
            "destination": destination.path,
            "count": "\(items.count)"
        ])

        try throwIfCancelled(cancellation)
        try runZipCreate(items: items, parentDirectory: parentDirectory, destination: destination, cancellation: cancellation)

        progress?(items.count, items.count)
        logger?.info("archive", "compress.completed", metadata: ["destination": destination.path])
        return destination.standardizedFileURL
    }

    public func extract(
        archives: [URL],
        mode: ArchiveExtractionMode,
        cancellation: FileOperationCancellation? = nil,
        progress: ((Int, Int) -> Void)? = nil
    ) throws {
        let items = Self.extractableArchives(from: archives)
        guard !items.isEmpty else { throw ArchiveError.noArchives }
        let total = items.count

        var processed = 0
        for archive in items {
            try throwIfCancelled(cancellation)
            guard let format = ArchiveFormatDetector.format(for: archive) else {
                processed += 1
                progress?(processed, total)
                continue
            }
            let parent = archive.deletingLastPathComponent()
            let destinationDirectory = try extractionDestination(
                for: archive,
                parent: parent,
                mode: mode
            )
            if !fileManager.fileExists(atPath: destinationDirectory.path) {
                try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
            }

            logger?.info("archive", "extract.started", metadata: [
                "archive": archive.path,
                "destination": destinationDirectory.path,
                "format": format.rawValue,
                "mode": mode == .currentDirectory ? "here" : "subfolder"
            ])

            try throwIfCancelled(cancellation)
            try runExtract(archive: archive, format: format, destination: destinationDirectory, cancellation: cancellation)
            if format == .zip {
                repairLegacyZipEntryNames(in: destinationDirectory, archive: archive)
            }

            processed += 1
            progress?(processed, total)

            logger?.info("archive", "extract.completed", metadata: [
                "archive": archive.path,
                "destination": destinationDirectory.path
            ])
        }
    }

    private func throwIfCancelled(_ cancellation: FileOperationCancellation?) throws {
        if cancellation?.isCancelled == true {
            throw ArchiveError.cancelled
        }
    }

    private func zipBaseName(for items: [URL]) -> String {
        if items.count == 1 {
            return FileNameUtilities.baseName(for: items[0].lastPathComponent)
        }
        return "Archive"
    }

    private func uniqueArchiveURL(named name: String, in directory: URL) -> URL {
        var destination = directory.appendingPathComponent(name)
        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            let base = FileNameUtilities.baseName(for: name)
            let ext = FileNameUtilities.extensionName(for: name)
            let nextName = ext.isEmpty
                ? FileNameUtilities.numberedCopyName(for: base, index: index)
                : "\(FileNameUtilities.numberedCopyName(for: base, index: index)).\(ext)"
            destination = directory.appendingPathComponent(nextName)
            index += 1
        }
        return destination
    }

    private func extractionDestination(
        for archive: URL,
        parent: URL,
        mode: ArchiveExtractionMode
    ) throws -> URL {
        switch mode {
        case .currentDirectory:
            return parent.standardizedFileURL
        case .namedSubfolder:
            let folderName = ArchiveFormatDetector.extractionFolderName(for: archive)
            return uniqueArchiveURL(named: folderName, in: parent)
        }
    }

    private func runZipCreate(items: [URL], parentDirectory: URL, destination: URL, cancellation: FileOperationCancellation?) throws {
        #if os(macOS)
        var arguments = ["-r", "-q", destination.path]
        arguments.append(contentsOf: items.map(\.lastPathComponent))
        try runRequiredCommand(
            commandLabel: "zip",
            executables: ["/usr/bin/zip"],
            arguments: arguments,
            workingDirectory: parentDirectory,
            cancellation: cancellation
        )
        #elseif os(Windows)
        throw ArchiveError.unsupportedFormat(.zip)
        #else
        throw ArchiveError.unsupportedFormat(.zip)
        #endif
    }

    private func runExtract(archive: URL, format: ArchiveFormat, destination: URL, cancellation: FileOperationCancellation?) throws {
        switch format {
        case .zip:
            try extractZip(archive: archive, destination: destination, cancellation: cancellation)
        case .tar, .tarGzip, .tarBzip2, .tarXz, .gzip, .bzip2, .xz:
            try extractTarFamily(archive: archive, destination: destination, cancellation: cancellation)
        case .sevenZip, .rar, .iso:
            try extractWithExternalTool(archive: archive, destination: destination, cancellation: cancellation)
        }
    }

    /// macOS's ditto decodes ZIP names without the UTF-8 flag as MacRoman. Many
    /// Windows tools write Chinese names as GBK instead, so repair the extracted
    /// paths from the original central-directory bytes while that information is
    /// still available. UTF-8 names and ordinary non-CJK names are left alone.
    private func repairLegacyZipEntryNames(in destination: URL, archive: URL) {
        guard let data = try? Data(contentsOf: archive) else { return }
        let repairs = LegacyZipFilenameRepair.repairs(in: data)
        guard !repairs.isEmpty else { return }

        for repair in repairs {
            let target = destination.appendingPathComponent(repair.repaired)
            guard !fileManager.fileExists(atPath: target.path) else { continue }

            for sourceRelativePath in LegacyZipFilenameRepair.sourceCandidates(for: repair) {
                let source = destination.appendingPathComponent(sourceRelativePath)
                guard source != target,
                      fileManager.fileExists(atPath: source.path) else {
                    continue
                }

                do {
                    try fileManager.moveItem(at: source, to: target)
                    break
                } catch {
                    logger?.warning("archive", "extract.legacy-name-repair-failed", metadata: [
                        "source": source.path,
                        "target": target.path,
                        "error": error.localizedDescription
                    ])
                }
            }
        }

        let repairedCount = repairs.reduce(into: 0) { count, repair in
            if fileManager.fileExists(atPath: destination.appendingPathComponent(repair.repaired).path) {
                count += 1
            }
        }
        if repairedCount > 0 {
            logger?.info("archive", "extract.legacy-names-repaired", metadata: [
                "archive": archive.path,
                "count": "\(repairedCount)"
            ])
        }
    }

    private func extractZip(archive: URL, destination: URL, cancellation: FileOperationCancellation?) throws {
        #if os(macOS)
        if fileManager.fileExists(atPath: "/usr/bin/ditto") {
            try runRequiredCommand(
                commandLabel: "ditto",
                executables: ["/usr/bin/ditto"],
                arguments: ["-xk", archive.path, destination.path],
                workingDirectory: nil,
                cancellation: cancellation
            )
            return
        }
        try runRequiredCommand(
            commandLabel: "unzip",
            executables: ["/usr/bin/unzip"],
            arguments: ["-qq", "-d", destination.path, archive.path],
            workingDirectory: nil,
            cancellation: cancellation
        )
        #elseif os(Windows)
        try runRequiredCommand(
            commandLabel: "tar",
            executables: ["tar.exe"],
            arguments: ["-xf", archive.path, "-C", destination.path],
            workingDirectory: nil,
            cancellation: cancellation
        )
        #else
        throw ArchiveError.unsupportedFormat(.zip)
        #endif
    }

    private func extractTarFamily(archive: URL, destination: URL, cancellation: FileOperationCancellation?) throws {
        #if os(macOS)
        try runRequiredCommand(
            commandLabel: "tar",
            executables: ["/usr/bin/tar"],
            arguments: ["-xf", archive.path, "-C", destination.path],
            workingDirectory: nil,
            cancellation: cancellation
        )
        #elseif os(Windows)
        try runRequiredCommand(
            commandLabel: "tar",
            executables: ["tar.exe"],
            arguments: ["-xf", archive.path, "-C", destination.path],
            workingDirectory: nil,
            cancellation: cancellation
        )
        #else
        throw ArchiveError.unsupportedFormat(.tar)
        #endif
    }

    private func extractWithExternalTool(archive: URL, destination: URL, cancellation: FileOperationCancellation?) throws {
        let toolCandidates = sevenZipExecutables() + unarExecutables()
        guard !toolCandidates.isEmpty else {
            throw ArchiveError.toolNotFound("7z or unar")
        }

        var lastError: Error?
        for executable in toolCandidates {
            do {
                if executable.hasSuffix("unar") || executable.contains("unar") {
                    try runRequiredCommand(
                        commandLabel: "unar",
                        executables: [executable],
                        arguments: ["-q", "-o", destination.path, archive.path],
                        workingDirectory: nil,
                        cancellation: cancellation
                    )
                } else {
                    try runRequiredCommand(
                        commandLabel: "7z",
                        executables: [executable],
                        arguments: ["x", "-y", "-o\(destination.path)", archive.path],
                        workingDirectory: nil,
                        cancellation: cancellation
                    )
                }
                return
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ArchiveError.toolNotFound("7z or unar")
    }

    private func sevenZipExecutables() -> [String] {
        #if os(macOS)
        let candidates = [
            "/opt/homebrew/bin/7z",
            "/usr/local/bin/7z",
            "/usr/bin/7z"
        ]
        return candidates.filter { fileManager.isExecutableFile(atPath: $0) }
        #elseif os(Windows)
        let candidates = [
            "C:\\Program Files\\7-Zip\\7z.exe",
            "C:\\Program Files (x86)\\7-Zip\\7z.exe"
        ]
        return candidates.filter { fileManager.isExecutableFile(atPath: $0) }
        #else
        return []
        #endif
    }

    private func unarExecutables() -> [String] {
        #if os(macOS)
        let candidates = [
            "/opt/homebrew/bin/unar",
            "/usr/local/bin/unar",
            "/usr/bin/unar"
        ]
        return candidates.filter { fileManager.isExecutableFile(atPath: $0) }
        #else
        return []
        #endif
    }

    private func runRequiredCommand(
        commandLabel: String,
        executables: [String],
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?
    ) throws {
        guard let executable = executables.first(where: { fileManager.isExecutableFile(atPath: $0) }) else {
            throw ArchiveError.toolNotFound(commandLabel)
        }

        let result: CommandResult
        do {
            if let cancellable = commandRunner as? any CancellableCommandRunning {
                result = try cancellable.run(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory,
                    cancellation: cancellation
                )
            } else {
                result = try commandRunner.run(
                    executable: executable,
                    arguments: arguments,
                    workingDirectory: workingDirectory
                )
            }
        } catch FileOperationError.cancelled {
            throw ArchiveError.cancelled
        }
        guard result.succeeded else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallback = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty ? fallback : detail
            throw ArchiveError.commandFailed(
                command: ([executable] + arguments).joined(separator: " "),
                exitCode: result.exitCode,
                detail: message.isEmpty ? "No error output." : message
            )
        }
    }
}

private enum LegacyZipFilenameRepair {
    struct PathRepair {
        let rendered: String
        let repaired: String
    }

    private struct EncodingCandidate {
        let encoding: String.Encoding
        let priority: Int
    }

    private static let candidates: [EncodingCandidate] = [
        encoding(named: "GB18030").map { EncodingCandidate(encoding: $0, priority: 3) },
        encoding(named: "Big5").map { EncodingCandidate(encoding: $0, priority: 2) },
        EncodingCandidate(encoding: .shiftJIS, priority: 1)
    ].compactMap { $0 }

    static func repairs(in archive: Data) -> [PathRepair] {
        let bytes = [UInt8](archive)
        guard let endOfCentralDirectory = findEndOfCentralDirectory(in: bytes),
              let entryCount = readUInt16(bytes, at: endOfCentralDirectory + 10),
              let centralDirectoryOffset = readUInt32(bytes, at: endOfCentralDirectory + 16) else {
            return []
        }

        var offset = Int(centralDirectoryOffset)
        var pathRepairs: [String: String] = [:]
        for _ in 0..<entryCount {
            guard readUInt32(bytes, at: offset) == 0x0201_4B50,
                  let flags = readUInt16(bytes, at: offset + 8),
                  let nameLength = readUInt16(bytes, at: offset + 28),
                  let extraLength = readUInt16(bytes, at: offset + 30),
                  let commentLength = readUInt16(bytes, at: offset + 32) else {
                break
            }

            let nameStart = offset + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= bytes.count else { break }
            let rawName = Array(bytes[nameStart..<nameEnd])
            if flags & 0x0800 == 0 {
                let extraStart = nameEnd
                let extraEnd = extraStart + Int(extraLength)
                let unicodePath = unicodePath(
                    in: Array(bytes[extraStart..<extraEnd]),
                    rawName: rawName
                )
                addRepairs(for: rawName, unicodePath: unicodePath, to: &pathRepairs)
            }

            offset = nameEnd + Int(extraLength) + Int(commentLength)
            guard offset <= bytes.count else { break }
        }

        return pathRepairs.map { PathRepair(rendered: $0.key, repaired: $0.value) }.sorted {
            pathDepth($0.rendered) < pathDepth($1.rendered)
        }
    }

    static func sourceCandidates(for repair: PathRepair) -> [String] {
        let renderedComponents = repair.rendered.split(separator: "/").map(String.init)
        let repairedComponents = repair.repaired.split(separator: "/").map(String.init)
        guard renderedComponents.count == repairedComponents.count else {
            return [repair.rendered]
        }

        var candidates: [[String]] = [[]]
        for (rendered, repaired) in zip(renderedComponents, repairedComponents) {
            candidates = candidates.flatMap { prefix in
                [prefix + [rendered], prefix + [repaired]]
            }
        }
        return Array(Set(candidates.map { $0.joined(separator: "/") }))
    }

    private static func addRepairs(
        for rawName: [UInt8],
        unicodePath: String?,
        to repairs: inout [String: String]
    ) {
        let rawComponents = rawName
            .split(separator: 0x2F, omittingEmptySubsequences: true)
            .map(Array.init)
            .filter { $0 != [0x2E] }
        guard !rawComponents.isEmpty,
              !rawComponents.contains([0x2E, 0x2E]) else { return }

        var macRomanRenderedComponents: [String] = []
        var extractorRenderedComponents: [String] = []
        var repairedComponents: [String] = []
        for rawComponent in rawComponents {
            // ZIPs produced by some Windows tools can mix UTF-8 and GBK
            // components in one path while leaving the UTF-8 flag unset.
            let isUTF8 = String(data: Data(rawComponent), encoding: .utf8) != nil
            let macRomanRendered = decode(rawComponent, as: .macOSRoman)
            let extractorRendered = decode(rawComponent, as: isUTF8 ? .utf8 : .macOSRoman)
            let repaired = isUTF8 ? extractorRendered : (legacyCJKName(for: rawComponent) ?? extractorRendered)
            macRomanRenderedComponents.append(macRomanRendered)
            extractorRenderedComponents.append(extractorRendered)
            repairedComponents.append(repaired)
        }

        let targetComponents = unicodePath
            .flatMap(pathComponents)
            ?? repairedComponents
        guard targetComponents.count == rawComponents.count else { return }

        addRepairs(
            renderedComponents: macRomanRenderedComponents,
            repairedComponents: targetComponents,
            to: &repairs
        )
        if extractorRenderedComponents != macRomanRenderedComponents {
            addRepairs(
                renderedComponents: extractorRenderedComponents,
                repairedComponents: targetComponents,
                to: &repairs
            )
        }
    }

    private static func addRepairs(
        renderedComponents: [String],
        repairedComponents: [String],
        to repairs: inout [String: String]
    ) {
        for depth in 1...renderedComponents.count {
            let renderedPath = renderedComponents.prefix(depth).joined(separator: "/")
            let repairedPath = repairedComponents.prefix(depth).joined(separator: "/")
            if renderedPath != repairedPath {
                if let existing = repairs[renderedPath], existing != repairedPath {
                    continue
                }
                repairs[renderedPath] = repairedPath
            }
        }
    }

    private static func legacyCJKName(for bytes: [UInt8]) -> String? {
        guard bytes.contains(where: { $0 >= 0x80 }) else { return nil }
        return candidates
            .compactMap { candidate -> (String, Int)? in
                guard let decoded = String(data: Data(bytes), encoding: candidate.encoding),
                      !decoded.unicodeScalars.contains(where: { $0.value == 0 || $0.value < 0x20 }) else {
                    return nil
                }
                let cjkCount = decoded.unicodeScalars.filter(isCJK).count
                guard cjkCount > 0 else { return nil }
                return (decoded, cjkCount * 10 + candidate.priority)
            }
            .max { $0.1 < $1.1 }?.0
    }

    private static func decode(_ bytes: [UInt8], as encoding: String.Encoding) -> String {
        String(data: Data(bytes), encoding: encoding) ?? String(decoding: bytes, as: UTF8.self)
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x2E80...0x2FFF, 0x3400...0x4DBF, 0x4E00...0x9FFF, 0xF900...0xFAFF:
            return true
        default:
            return false
        }
    }

    private static func pathDepth(_ path: String) -> Int {
        path.split(separator: "/").count
    }

    private static func pathComponents(_ path: String) -> [String]? {
        let components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !components.isEmpty,
              !components.contains("."),
              !components.contains(".."),
              !path.hasPrefix("/") else { return nil }
        return components
    }

    private static func unicodePath(in extra: [UInt8], rawName: [UInt8]) -> String? {
        var offset = 0
        while offset + 4 <= extra.count {
            guard let tag = readUInt16(extra, at: offset),
                  let length = readUInt16(extra, at: offset + 2) else { return nil }
            let valueStart = offset + 4
            let valueEnd = valueStart + Int(length)
            guard valueEnd <= extra.count else { return nil }
            if tag == 0x7075,
               length >= 5,
               extra[valueStart] == 1,
               readUInt32(extra, at: valueStart + 1) == crc32(rawName),
               let path = String(data: Data(extra[(valueStart + 5)..<valueEnd]), encoding: .utf8) {
                return path
            }
            offset = valueEnd
        }
        return nil
    }

    private static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in bytes {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc >> 1) ^ ((crc & 1) == 1 ? 0xEDB8_8320 : 0)
            }
        }
        return crc ^ 0xFFFF_FFFF
    }

    private static func findEndOfCentralDirectory(in bytes: [UInt8]) -> Int? {
        guard !bytes.isEmpty else { return nil }
        let start = max(0, bytes.count - 65_557)
        guard bytes.count >= 22 else { return nil }
        for offset in stride(from: bytes.count - 22, through: start, by: -1) {
            if readUInt32(bytes, at: offset) == 0x0605_4B50 {
                return offset
            }
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= bytes.count else { return nil }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func readUInt32(_ bytes: [UInt8], at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= bytes.count else { return nil }
        return UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
    }

    private static func encoding(named name: String) -> String.Encoding? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
