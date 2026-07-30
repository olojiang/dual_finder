import Foundation

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
