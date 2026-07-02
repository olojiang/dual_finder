import Foundation

public enum FileOperationError: LocalizedError, Equatable {
    case trashUnsupported
    case emptyName
    case invalidName
    case cancelled
    case invalidDestination
    case emptySources
    case sourceIsDirectory(URL)

    public var errorDescription: String? {
        switch self {
        case .trashUnsupported:
            "Moving files to Trash is only supported on macOS."
        case .emptyName:
            "Name cannot be empty."
        case .invalidName:
            "Name contains characters that cannot be used in a file name."
        case .cancelled:
            "Operation cancelled."
        case .invalidDestination:
            "Destination cannot be the source item or one of its children."
        case .emptySources:
            "Select at least two files to merge."
        case let .sourceIsDirectory(url):
            "Cannot merge folder: \(url.lastPathComponent)"
        }
    }
}

public struct TrashContentsSummary: Equatable, Sendable {
    public let topLevelItemCount: Int
    public let containedItemCount: Int
    public let totalByteCount: Int64

    public init(topLevelItemCount: Int, containedItemCount: Int, totalByteCount: Int64) {
        self.topLevelItemCount = topLevelItemCount
        self.containedItemCount = containedItemCount
        self.totalByteCount = totalByteCount
    }

    public var isEmpty: Bool {
        topLevelItemCount == 0
    }
}

public struct FileOperationService {
    private let fileManager: FileManager
    private let logger: AppLogging?
    private let operationScanCache: OperationScanCache?

    public init(
        fileManager: FileManager = .default,
        logger: AppLogging?,
        operationScanCache: OperationScanCache? = nil
    ) {
        self.fileManager = fileManager
        self.logger = logger
        self.operationScanCache = operationScanCache
    }

    public func copy(
        _ sources: [URL],
        to destinationDirectory: URL,
        options: FileOperationOptions = FileOperationOptions(),
        cancellation: FileOperationCancellation? = nil,
        progress: ((FileOperationProgress) -> Void)? = nil,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)? = nil
    ) throws {
        logger?.info("file-operation", "copy.started", metadata: operationMetadata(sources, destinationDirectory))
        try processRootSources(
            sources,
            cancellation: cancellation,
            progress: progress
        ) { source, index, total in
            let context = try OperationContext(
                sources: [source],
                fileManager: fileManager,
                cancellation: cancellation,
                progress: progress,
                operationScanCache: operationScanCache,
                logger: logger,
                rootCompletedItems: index,
                rootTotalItems: total
            )
            try copySources(
                [source],
                to: destinationDirectory,
                options: options,
                context: context,
                conflictResolver: conflictResolver
            )
        }
        logger?.info("file-operation", "copy.completed", metadata: operationMetadata(sources, destinationDirectory))
    }

    public func mirror(
        _ sources: [URL],
        to destinationDirectory: URL,
        cancellation: FileOperationCancellation? = nil,
        progress: ((FileOperationProgress) -> Void)? = nil,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)? = nil
    ) throws {
        logger?.info("file-operation", "mirror.started", metadata: operationMetadata(sources, destinationDirectory))
        try copy(
            sources,
            to: destinationDirectory,
            options: FileOperationOptions(
                defaultConflictResolution: .overwrite,
                syncMode: true
            ),
            cancellation: cancellation,
            progress: progress,
            conflictResolver: conflictResolver
        )

        let extras = try MirrorDeletionPlanner.extrasToDelete(
            sources: sources,
            destinationDirectory: destinationDirectory,
            fileManager: fileManager
        )
        for url in extras {
            if cancellation?.isCancelled == true {
                throw FileOperationError.cancelled
            }
            try fileManager.removeItem(at: url)
            logger?.info("file-operation", "mirror.deleted-extra", metadata: [
                "path": url.path
            ])
        }
        var completedMetadata = operationMetadata(sources, destinationDirectory)
        completedMetadata["deletedItems"] = "\(extras.count)"
        logger?.info("file-operation", "mirror.completed", metadata: completedMetadata)
    }

    public func mirrorDeletionSummary(
        sources: [URL],
        destinationDirectory: URL
    ) throws -> MirrorDeletionSummary {
        try MirrorDeletionPlanner.deletionSummary(
            sources: sources,
            destinationDirectory: destinationDirectory,
            fileManager: fileManager
        )
    }

    public func move(
        _ sources: [URL],
        to destinationDirectory: URL,
        options: FileOperationOptions = FileOperationOptions(),
        cancellation: FileOperationCancellation? = nil,
        progress: ((FileOperationProgress) -> Void)? = nil,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)? = nil
    ) throws {
        logger?.info("file-operation", "move.started", metadata: operationMetadata(sources, destinationDirectory))
        if FileOperationVolume.canRenameMove(sources: sources, to: destinationDirectory) {
            do {
                try moveSourcesByRename(
                    sources,
                    to: destinationDirectory,
                    options: options,
                    cancellation: cancellation,
                    progress: progress,
                    conflictResolver: conflictResolver
                )
                logger?.info("file-operation", "move.completed", metadata: operationMetadata(sources, destinationDirectory))
                return
            } catch let error as MoveRenameFallbackError {
                logger?.warning("file-operation", "move.rename-fallback", metadata: [
                    "error": error.underlying.localizedDescription
                ])
            } catch {
                throw error
            }
        } else {
            logger?.info("file-operation", "move.using-copy-delete", metadata: [
                "reason": "cross-volume",
                "count": "\(sources.count)",
                "destination": destinationDirectory.path,
                "sources": sources.map(\.path).joined(separator: "|")
            ])
        }

        var copiedRoots: [CopiedRoot] = []
        do {
            try processRootSources(
                sources,
                cancellation: cancellation,
                progress: progress
            ) { source, index, total in
                let context = try OperationContext(
                    sources: [source],
                    fileManager: fileManager,
                    cancellation: cancellation,
                    progress: progress,
                    operationScanCache: operationScanCache,
                    logger: logger,
                    rootCompletedItems: index,
                    rootTotalItems: total
                )
                let copied = try copySources(
                    [source],
                    to: destinationDirectory,
                    options: options,
                    context: context,
                    conflictResolver: conflictResolver
                )
                copiedRoots.append(contentsOf: copied)
                for copiedRoot in copied {
                    try context.checkCancellation()
                    if copiedRoot.mergedIntoExistingDirectory {
                        logger?.info("file-operation", "move.merge.source-kept", metadata: [
                            "source": copiedRoot.source.path,
                            "destination": copiedRoot.destination.path,
                            "reason": "merged-into-existing-directory"
                        ])
                        continue
                    }
                    if fileManager.fileExists(atPath: copiedRoot.source.path) {
                        try fileManager.removeItem(at: copiedRoot.source)
                    }
                }
            }
        } catch {
            for copiedRoot in copiedRoots where fileManager.fileExists(atPath: copiedRoot.destination.path) {
                try? fileManager.removeItem(at: copiedRoot.destination)
            }
            throw error
        }
        logger?.info("file-operation", "move.completed", metadata: operationMetadata(sources, destinationDirectory))
    }

    public func createFolder(named name: String, in directory: URL) throws -> URL {
        let destination = uniqueDestination(for: name, in: directory)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        logger?.info("file-operation", "folder.created", metadata: ["path": destination.path])
        return destination.standardizedFileURL
    }

    public func createEmptyFile(named name: String, in directory: URL) throws -> URL {
        guard !FileNameUtilities.isBlank(name) else {
            throw FileOperationError.emptyName
        }

        let destination = uniqueDestination(for: name, in: directory)
        try Data().write(to: destination, options: .withoutOverwriting)
        logger?.info("file-operation", "file.created", metadata: ["path": destination.path])
        return destination.standardizedFileURL
    }

    public func rename(_ source: URL, to newName: String) throws -> URL {
        guard !FileNameUtilities.isBlank(newName) else {
            throw FileOperationError.emptyName
        }

        let sourceValues = try? source.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        let isDirectoryLike = sourceValues?.isDirectory == true || sourceValues?.isPackage == true
        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        let standardizedSource = source.standardizedFileURL
        let standardizedDestination = URL(fileURLWithPath: destination.path, isDirectory: isDirectoryLike).standardizedFileURL
        guard standardizedDestination != standardizedSource else {
            return standardizedSource
        }

        logger?.info("file-operation", "rename.started", metadata: [
            "source": source.path,
            "destination": destination.path
        ])
        try fileManager.moveItem(at: source, to: destination)
        logger?.info("file-operation", "rename.completed", metadata: [
            "source": source.path,
            "destination": destination.path
        ])
        return standardizedDestination
    }

    public func batchRename(_ operations: [BatchRenameOperation]) throws -> [URL] {
        let changes = try validatedBatchRenameChanges(operations)
        guard !changes.isEmpty else {
            logger?.info("file-operation", "batch-rename.noop")
            return operations.map(\.sourceURL.standardizedFileURL)
        }

        logger?.info("file-operation", "batch-rename.started", metadata: [
            "count": "\(changes.count)",
            "sources": changes.map { $0.source.path }.joined(separator: "|")
        ])

        var staged: [(temporary: URL, destination: URL, original: URL)] = []
        do {
            for change in changes {
                let temporary = uniqueTemporaryRenameURL(in: change.source.deletingLastPathComponent())
                try fileManager.moveItem(at: change.source, to: temporary)
                staged.append((temporary, change.destination, change.source))
            }

            for item in staged {
                try fileManager.moveItem(at: item.temporary, to: item.destination)
                logger?.info("file-operation", "batch-rename.item.completed", metadata: [
                    "source": item.original.path,
                    "destination": item.destination.path
                ])
            }
        } catch {
            rollback(staged)
            throw error
        }

        logger?.info("file-operation", "batch-rename.completed", metadata: [
            "count": "\(changes.count)"
        ])
        return operations.map(\.destinationURL)
    }

    public func mergeFiles(
        _ sources: [URL],
        named name: String,
        in directory: URL,
        trashSourcesAfterMerge: Bool = false
    ) throws -> URL {
        guard sources.count >= 2 else {
            throw FileOperationError.emptySources
        }
        guard !FileNameUtilities.isBlank(name) else {
            throw FileOperationError.emptyName
        }
        guard !FileNameUtilities.containsInvalidPathComponentCharacters(name) else {
            throw FileOperationError.invalidName
        }

        for source in sources {
            let values = try source.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                throw FileOperationError.sourceIsDirectory(source)
            }
        }

        let destination = uniqueDestination(for: name, in: directory)
        logger?.info("file-operation", "merge.started", metadata: operationMetadata(sources, directory))
        do {
            try Data().write(to: destination, options: .withoutOverwriting)
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }

            for (index, source) in sources.enumerated() {
                let endsWithLineBreak = try appendFile(source, to: output)
                if index < sources.index(before: sources.endIndex), !endsWithLineBreak {
                    try output.write(contentsOf: Data([0x0A]))
                }
            }
            logger?.info("file-operation", "merge.completed", metadata: [
                "path": destination.path,
                "count": "\(sources.count)"
            ])
            if trashSourcesAfterMerge {
                try trash(sources)
            }
            return destination.standardizedFileURL
        } catch {
            if fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            throw error
        }
    }

    public func trash(
        _ sources: [URL],
        cancellation: FileOperationCancellation? = nil,
        progress: ((FileOperationProgress) -> Void)? = nil
    ) throws {
        logger?.info("file-operation", "trash.started", metadata: ["count": "\(sources.count)"])
        let operationStart = Date()
        var completedItems = 0
        for source in sources {
            if cancellation?.isCancelled == true {
                throw FileOperationError.cancelled
            }
            #if os(macOS)
            try fileManager.trashItem(at: source, resultingItemURL: nil)
            #else
            throw FileOperationError.trashUnsupported
            #endif
            completedItems += 1
            progress?(FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: completedItems,
                totalItems: sources.count,
                currentItem: source,
                rootCompletedItems: completedItems,
                rootTotalItems: sources.count,
                elapsedSeconds: Date().timeIntervalSince(operationStart)
            ))
            logger?.warning("file-operation", "trash.item.completed", metadata: ["source": source.path])
        }
        logger?.info("file-operation", "trash.completed", metadata: ["count": "\(sources.count)"])
    }

    private func moveSourcesByRename(
        _ sources: [URL],
        to destinationDirectory: URL,
        options: FileOperationOptions,
        cancellation: FileOperationCancellation?,
        progress: ((FileOperationProgress) -> Void)?,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)?
    ) throws {
        let operationStart = Date()
        var completedItems = 0
        progress?(FileOperationProgress(
            completedBytes: 0,
            totalBytes: 0,
            completedItems: 0,
            totalItems: sources.count,
            currentItem: sources.first,
            rootCompletedItems: 0,
            rootTotalItems: sources.count,
            elapsedSeconds: 0
        ))

        for source in sources {
            if cancellation?.isCancelled == true {
                throw FileOperationError.cancelled
            }
            let destination = try resolvedDestination(
                for: source,
                requestedDestination: destinationDirectory.appendingPathComponent(source.lastPathComponent),
                options: options,
                conflictResolver: conflictResolver
            )
            guard let destination else { continue }

            logger?.info("file-operation", "move.rename.attempt", metadata: [
                "source": source.path,
                "destination": destination.path
            ])
            let renameStart = Date()
            do {
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                if completedItems == 0 {
                    throw MoveRenameFallbackError(underlying: error)
                }
                throw error
            }
            completedItems += 1
            progress?(FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: completedItems,
                totalItems: sources.count,
                currentItem: source,
                rootCompletedItems: completedItems,
                rootTotalItems: sources.count,
                elapsedSeconds: Date().timeIntervalSince(operationStart)
            ))
            logger?.info("file-operation", "move.item.renamed", metadata: [
                "source": source.path,
                "destination": destination.path,
                "elapsedMs": "\(Int(Date().timeIntervalSince(renameStart) * 1000))"
            ])
        }
    }


    private func processRootSources(
        _ sources: [URL],
        cancellation: FileOperationCancellation?,
        progress: ((FileOperationProgress) -> Void)?,
        handler: (_ source: URL, _ index: Int, _ total: Int) throws -> Void
    ) throws {
        let total = sources.count
        for (index, source) in sources.enumerated() {
            if cancellation?.isCancelled == true {
                throw FileOperationError.cancelled
            }
            progress?(FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: 0,
                totalItems: 0,
                currentItem: source,
                rootCompletedItems: index,
                rootTotalItems: total,
                elapsedSeconds: 0
            ))
            try handler(source, index, total)
        }
    }

    @discardableResult
    private func copySources(
        _ sources: [URL],
        to destinationDirectory: URL,
        options: FileOperationOptions,
        context: OperationContext,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)?
    ) throws -> [CopiedRoot] {
        var copiedRoots: [CopiedRoot] = []
        for source in sources {
            try context.checkCancellation()
            let requestedDestination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            let mergedIntoExistingDirectory = fileManager.fileExists(atPath: requestedDestination.path)
                && isMergeableDirectory(source)
                && isMergeableDirectory(requestedDestination)
            let destination = try resolvedDestination(
                for: source,
                requestedDestination: requestedDestination,
                options: options,
                conflictResolver: conflictResolver
            )
            guard let destination else { continue }

            try copyItem(
                at: source,
                to: destination,
                options: options,
                context: context,
                conflictResolver: conflictResolver
            )
            copiedRoots.append(CopiedRoot(
                source: source,
                destination: destination,
                mergedIntoExistingDirectory: mergedIntoExistingDirectory
            ))
            logger?.info("file-operation", "copy.item.completed", metadata: [
                "source": source.path,
                "destination": destination.path
            ])
        }
        return copiedRoots
    }

    private func copyItem(
        at source: URL,
        to destination: URL,
        options: FileOperationOptions,
        context: OperationContext,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)?
    ) throws {
        try context.checkCancellation()
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values.isDirectory == true && values.isSymbolicLink != true {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            try context.finishItem(source)
            let children = try fileManager.contentsOfDirectory(
                at: source,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            )
            for child in children {
                let childDestination = try resolvedDestination(
                    for: child,
                    requestedDestination: destination.appendingPathComponent(child.lastPathComponent),
                    options: options,
                    context: context,
                    conflictResolver: conflictResolver
                )
                guard let childDestination else { continue }
                try copyItem(
                    at: child,
                    to: childDestination,
                    options: options,
                    context: context,
                    conflictResolver: conflictResolver
                )
            }
        } else if values.isRegularFile == true {
            try copyRegularFile(at: source, to: destination, context: context)
        } else {
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
            try context.finishItem(source, copied: true)
        }
    }

    private func copyRegularFile(at source: URL, to destination: URL, context: OperationContext) throws {
        try context.checkCancellation()
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            fileManager.createFile(atPath: destination.path, contents: nil)

            let input = try FileHandle(forReadingFrom: source)
            let output = try FileHandle(forWritingTo: destination)
            defer {
                try? input.close()
                try? output.close()
            }

            while true {
                try context.checkCancellation()
                let shouldContinue: Bool = try autoreleasepool {
                    let data = try input.read(upToCount: 1024 * 1024) ?? Data()
                    guard !data.isEmpty else { return false }
                    try output.write(contentsOf: data)
                    context.advance(bytes: Int64(data.count), currentItem: source)
                    return true
                }
                if !shouldContinue { break }
            }
            try context.finishItem(source, copied: true)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
    }

    private func resolvedDestination(
        for source: URL,
        requestedDestination: URL,
        options: FileOperationOptions,
        context: OperationContext? = nil,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)?
    ) throws -> URL? {
        let conflict = FileOperationConflict(source: source, destination: requestedDestination)

        guard source.standardizedFileURL != requestedDestination.standardizedFileURL else {
            let resolution = Self.resolvedStrategy(
                for: conflict,
                options: options,
                conflictResolver: conflictResolver
            )
            switch resolution {
            case .overwrite:
                throw FileOperationError.invalidDestination
            case .skip:
                return nil
            case .keepBoth:
                return uniqueDestination(for: requestedDestination.lastPathComponent, in: requestedDestination.deletingLastPathComponent())
            case .largerWins:
                preconditionFailure("largerWins should be resolved to a concrete strategy before this switch")
            }
        }

        try validateDestination(requestedDestination, forCopying: source)

        guard fileManager.fileExists(atPath: requestedDestination.path) else {
            return requestedDestination
        }

        if shouldMergeDirectories(source: source, into: requestedDestination) {
            logger?.info("file-operation", "conflict.merge-directories", metadata: [
                "source": source.path,
                "destination": requestedDestination.path
            ])
            return requestedDestination
        }

        if options.syncMode, isSameFileContent(source: source, destination: requestedDestination) {
            logger?.debug("file-operation", "sync.skip-identical", metadata: [
                "source": source.path,
                "destination": requestedDestination.path
            ])
            try context?.recordSkipped(source)
            return nil
        }

        let resolution = Self.resolvedStrategy(
            for: conflict,
            options: options,
            conflictResolver: conflictResolver
        )

        switch resolution {
        case .overwrite:
            try fileManager.removeItem(at: requestedDestination)
            return requestedDestination
        case .skip:
            logger?.info("file-operation", "conflict.skip", metadata: [
                "source": source.path,
                "destination": requestedDestination.path
            ])
            try context?.recordSkipped(source)
            return nil
        case .keepBoth:
            return uniqueDestination(for: requestedDestination.lastPathComponent, in: requestedDestination.deletingLastPathComponent())
        case .largerWins:
            preconditionFailure("largerWins should be resolved to a concrete strategy before this switch")
        }
    }

    private static func resolvedStrategy(
        for conflict: FileOperationConflict,
        options: FileOperationOptions,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)?
    ) -> FileOperationConflictResolution {
        let resolution = conflictResolver?(conflict) ?? options.defaultConflictResolution
        return resolution == .largerWins ? largerWinsResolution(for: conflict) : resolution
    }

    private func validateDestination(_ destination: URL, forCopying source: URL) throws {
        let values = try source.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true && values.isSymbolicLink != true else { return }

        let sourcePath = source.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard destinationPath == sourcePath || destinationPath.hasPrefix(sourcePath + "/") else { return }
        throw FileOperationError.invalidDestination
    }

    public func trashContentsSummary(at trashDirectory: URL = .trashDirectory) throws -> TrashContentsSummary {
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey
        ]
        let trashedItems = try userVisibleTrashItems(
            at: trashDirectory,
            includingPropertiesForKeys: resourceKeys
        )

        var containedItemCount = 0
        var totalByteCount: Int64 = 0
        for item in trashedItems {
            let summary = trashItemSummary(at: item, resourceKeys: resourceKeys)
            containedItemCount += summary.itemCount
            totalByteCount += summary.byteCount
        }

        return TrashContentsSummary(
            topLevelItemCount: trashedItems.count,
            containedItemCount: containedItemCount,
            totalByteCount: totalByteCount
        )
    }

    public func emptyTrash(at trashDirectory: URL = .trashDirectory) throws -> Int {
        let trashedItems = try userVisibleTrashItems(
            at: trashDirectory,
            includingPropertiesForKeys: nil
        )

        logger?.warning("file-operation", "trash.empty.started", metadata: [
            "path": trashDirectory.path,
            "count": "\(trashedItems.count)"
        ])
        for item in trashedItems {
            try fileManager.removeItem(at: item)
            logger?.warning("file-operation", "trash.empty.item.removed", metadata: [
                "path": item.path
            ])
        }
        logger?.warning("file-operation", "trash.empty.completed", metadata: [
            "path": trashDirectory.path,
            "count": "\(trashedItems.count)"
        ])
        return trashedItems.count
    }

    private func userVisibleTrashItems(
        at trashDirectory: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?
    ) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: trashDirectory,
            includingPropertiesForKeys: keys
        )
        .filter { !Self.isTrashMetadataItem($0) }
    }

    private static func isTrashMetadataItem(_ url: URL) -> Bool {
        switch url.lastPathComponent {
        case ".DS_Store", ".localized":
            true
        default:
            false
        }
    }

    private func trashItemSummary(at url: URL, resourceKeys: [URLResourceKey]) -> (itemCount: Int, byteCount: Int64) {
        var itemCount = 1
        var byteCount = removableFileSize(at: url)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values?.isDirectory == true, values?.isSymbolicLink != true else {
            return (itemCount, byteCount)
        }

        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: resourceKeys,
            errorHandler: { _, _ in true }
        ) else {
            return (itemCount, byteCount)
        }

        for case let child as URL in enumerator {
            itemCount += 1
            byteCount += removableFileSize(at: child)
        }
        return (itemCount, byteCount)
    }

    private func removableFileSize(at url: URL) -> Int64 {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]),
              values.isRegularFile == true || values.isSymbolicLink == true else {
            return 0
        }
        return Int64(values.fileSize ?? 0)
    }

    private func uniqueDestination(for name: String, in directory: URL) -> URL {
        var destination = directory.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: destination.path) else {
            return destination
        }

        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(FileNameUtilities.numberedCopyName(for: name, index: index))
            index += 1
        }
        return destination
    }

    private func validatedBatchRenameChanges(_ operations: [BatchRenameOperation]) throws -> [(source: URL, destination: URL)] {
        var destinationPaths = Set<String>()
        let changes = try operations.compactMap { operation -> (source: URL, destination: URL)? in
            guard !FileNameUtilities.isBlank(operation.newName) else {
                throw BatchRenameError.emptyName(operation.sourceURL)
            }
            guard !FileNameUtilities.containsInvalidPathComponentCharacters(operation.newName) else {
                throw BatchRenameError.invalidName(operation.newName)
            }

            let source = operation.sourceURL.standardizedFileURL
            let destination = operation.destinationURL.standardizedFileURL
            guard source != destination else { return nil }
            guard destinationPaths.insert(destination.path).inserted else {
                throw BatchRenameError.duplicateDestination(destination)
            }
            return (source, destination)
        }

        let changedSourcePaths = Set(changes.map(\.source.path))
        for change in changes where fileManager.fileExists(atPath: change.destination.path) {
            guard changedSourcePaths.contains(change.destination.path) else {
                throw BatchRenameError.destinationExists(change.destination)
            }
        }

        return changes
    }

    private func uniqueTemporaryRenameURL(in directory: URL) -> URL {
        var destination: URL
        repeat {
            destination = directory.appendingPathComponent(".dualfinder-rename-\(UUID().uuidString).tmp")
        } while fileManager.fileExists(atPath: destination.path)
        return destination
    }

    private func appendFile(_ source: URL, to output: FileHandle) throws -> Bool {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }

        var lastChunk = Data()
        while true {
            guard let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty else {
                break
            }
            lastChunk = chunk
            try output.write(contentsOf: chunk)
        }
        return endsWithLineBreak(lastChunk)
    }

    private func endsWithLineBreak(_ data: Data) -> Bool {
        guard let last = data.last else { return true }
        return last == 0x0A || last == 0x0D
    }

    private func rollback(_ staged: [(temporary: URL, destination: URL, original: URL)]) {
        for item in staged.reversed() where fileManager.fileExists(atPath: item.temporary.path) {
            do {
                if fileManager.fileExists(atPath: item.original.path) {
                    try fileManager.removeItem(at: item.temporary)
                } else {
                    try fileManager.moveItem(at: item.temporary, to: item.original)
                }
            } catch {
                logger?.error("file-operation", "batch-rename.rollback.failed", metadata: [
                    "temporary": item.temporary.path,
                    "original": item.original.path,
                    "error": error.localizedDescription
                ])
            }
        }
    }

    private func operationMetadata(_ sources: [URL], _ destination: URL) -> [String: String] {
        [
            "count": "\(sources.count)",
            "destination": destination.path,
            "sources": sources.map(\.path).joined(separator: "|")
        ]
    }

    private final class OperationContext {
        private let cancellation: FileOperationCancellation?
        private let progress: ((FileOperationProgress) -> Void)?
        private let operationStart = Date()
        private let totalBytes: Int64
        private let totalItems: Int
        private var completedBytes: Int64 = 0
        private var completedItems: Int = 0
        private var copiedItems: Int = 0
        private var copiedBytes: Int64 = 0
        private var skippedItems: Int = 0
        private var skippedBytes: Int64 = 0
        private var skippedUpdatesSincePublish = 0
        private var lastPublishedBytes: Int64 = 0
        private var lastPublishedAt = Date()

        private let rootCompletedItems: Int
        private let rootTotalItems: Int
        private let operationScanCache: OperationScanCache?
        private let logger: AppLogging?

        init(
            sources: [URL],
            fileManager: FileManager,
            cancellation: FileOperationCancellation?,
            progress: ((FileOperationProgress) -> Void)?,
            operationScanCache: OperationScanCache?,
            logger: AppLogging?,
            rootCompletedItems: Int = 0,
            rootTotalItems: Int = 0
        ) throws {
            self.cancellation = cancellation
            self.progress = progress
            self.rootCompletedItems = rootCompletedItems
            self.rootTotalItems = rootTotalItems
            self.operationScanCache = operationScanCache
            self.logger = logger
            var plan = OperationPlan()
            var scannedItems = 0
            let startedAt = Date()
            func reportScanning(_ count: Int, currentItem: URL?) {
                progress?(FileOperationProgress(
                    completedBytes: 0,
                    totalBytes: 0,
                    completedItems: 0,
                    totalItems: 0,
                    currentItem: currentItem,
                    scannedItems: count,
                    rootCompletedItems: rootCompletedItems,
                    rootTotalItems: rootTotalItems,
                    elapsedSeconds: Date().timeIntervalSince(startedAt)
                ))
            }
            reportScanning(0, currentItem: sources.first)
            for source in sources {
                let modifiedAt = try source.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                logger?.info("file-operation", "scan.started", metadata: [
                    "path": source.path,
                    "modifiedAt": modifiedAt.map { "\($0.timeIntervalSince1970)" } ?? "nil"
                ])
                if sources.count == 1,
                   let cachedPlan = operationScanCache?.plan(for: source, modifiedAt: modifiedAt) {
                    plan.totalBytes = cachedPlan.totalBytes
                    plan.totalItems = cachedPlan.totalItems
                    logger?.info("file-operation", "scan.cache.hit", metadata: [
                        "path": source.path,
                        "totalBytes": "\(cachedPlan.totalBytes)",
                        "totalItems": "\(cachedPlan.totalItems)"
                    ])
                } else {
                    var lastProgressLog = startedAt
                    try Self.scan(source, fileManager: fileManager, plan: &plan) { item in
                        scannedItems += 1
                        if scannedItems == 1 || scannedItems % 100 == 0 {
                            reportScanning(scannedItems, currentItem: item)
                        }
                        let now = Date()
                        if now.timeIntervalSince(lastProgressLog) >= 5 {
                            logger?.info("file-operation", "scan.progress", metadata: [
                                "path": source.path,
                                "scannedItems": "\(scannedItems)",
                                "elapsedMs": "\(Int(now.timeIntervalSince(startedAt) * 1000))"
                            ])
                            lastProgressLog = now
                        }
                    }
                    logger?.info("file-operation", "scan.completed", metadata: [
                        "path": source.path,
                        "scannedItems": "\(scannedItems)",
                        "totalBytes": "\(plan.totalBytes)",
                        "totalItems": "\(plan.totalItems)",
                        "elapsedMs": "\(Int(Date().timeIntervalSince(startedAt) * 1000))"
                    ])
                    if sources.count == 1 {
                        let scanPlan = OperationScanPlan(totalBytes: plan.totalBytes, totalItems: plan.totalItems)
                        try operationScanCache?.setPlan(scanPlan, for: source, modifiedAt: modifiedAt)
                        logger?.info("file-operation", "scan.cache.saved", metadata: [
                            "path": source.path,
                            "totalBytes": "\(scanPlan.totalBytes)",
                            "totalItems": "\(scanPlan.totalItems)"
                        ])
                    }
                }
            }
            totalBytes = plan.totalBytes
            totalItems = plan.totalItems
            publish(currentItem: sources.first)
        }

        func checkCancellation() throws {
            if cancellation?.isCancelled == true {
                throw FileOperationError.cancelled
            }
        }

        func advance(bytes: Int64, currentItem: URL?) {
            completedBytes += bytes
            let now = Date()
            let byteDelta = completedBytes - lastPublishedBytes
            if byteDelta >= 8 * 1024 * 1024 || now.timeIntervalSince(lastPublishedAt) >= 0.5 {
                lastPublishedBytes = completedBytes
                lastPublishedAt = now
                publish(currentItem: currentItem)
            }
        }

        func finishItem(_ currentItem: URL?, copied: Bool = false) throws {
            try checkCancellation()
            completedItems += 1
            if copied, let currentItem {
                copiedItems += 1
                copiedBytes += Self.itemByteSize(currentItem)
            }
            lastPublishedBytes = completedBytes
            lastPublishedAt = Date()
            publish(currentItem: currentItem)
        }

        func recordSkipped(_ source: URL) throws {
            try checkCancellation()
            skippedItems += 1
            skippedUpdatesSincePublish += 1
            let size = Self.itemByteSize(source)
            skippedBytes += size
            completedBytes += size
            completedItems += 1
            let now = Date()
            if skippedUpdatesSincePublish >= 100 || now.timeIntervalSince(lastPublishedAt) >= 0.5 {
                skippedUpdatesSincePublish = 0
                lastPublishedBytes = completedBytes
                lastPublishedAt = now
                publish(currentItem: source)
            }
        }

        private static func itemByteSize(_ url: URL) -> Int64 {
            guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .fileSizeKey]) else {
                return 0
            }
            if values.isDirectory == true {
                return 0
            }
            return Int64(values.fileSize ?? 0)
        }

        private func publish(currentItem: URL?) {
            progress?(FileOperationProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                completedItems: completedItems,
                totalItems: totalItems,
                currentItem: currentItem,
                copiedItems: copiedItems,
                copiedBytes: copiedBytes,
                skippedItems: skippedItems,
                skippedBytes: skippedBytes,
                rootCompletedItems: rootCompletedItems,
                rootTotalItems: rootTotalItems,
                elapsedSeconds: Date().timeIntervalSince(operationStart)
            ))
        }

        private static func scan(
            _ url: URL,
            fileManager: FileManager,
            plan: inout OperationPlan,
            onItemScanned: (URL) -> Void
        ) throws {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            plan.totalItems += 1
            onItemScanned(url)
            if values.isRegularFile == true {
                plan.totalBytes += Int64(values.fileSize ?? 0)
                return
            }

            guard values.isDirectory == true && values.isSymbolicLink != true else { return }
            let children = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
                options: []
            )
            for child in children {
                try scan(child, fileManager: fileManager, plan: &plan, onItemScanned: onItemScanned)
            }
        }
    }

    private struct OperationPlan {
        var totalBytes: Int64 = 0
        var totalItems: Int = 0
    }

    private struct CopiedRoot {
        let source: URL
        let destination: URL
        let mergedIntoExistingDirectory: Bool
    }

    private struct MoveRenameFallbackError: Error {
        let underlying: Error
    }

    public static func largerWinsResolution(for conflict: FileOperationConflict) -> FileOperationConflictResolution {
        guard let sourceSize = fileSize(at: conflict.source),
              let destinationSize = fileSize(at: conflict.destination)
        else {
            return .skip
        }
        return sourceSize >= destinationSize ? .overwrite : .skip
    }

    private static func fileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return nil }
        return values?.fileSize.map(Int64.init)
    }

    private func shouldMergeDirectories(source: URL, into destination: URL) -> Bool {
        isMergeableDirectory(source) && isMergeableDirectory(destination)
    }

    private func isMergeableDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values?.isDirectory == true && values?.isSymbolicLink != true
    }

    private func isSameFileContent(source: URL, destination: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let sourceValues = try? source.resourceValues(forKeys: keys),
              let destinationValues = try? destination.resourceValues(forKeys: keys),
              sourceValues.isRegularFile == true,
              destinationValues.isRegularFile == true else {
            return false
        }
        return sourceValues.fileSize == destinationValues.fileSize
            && sourceValues.contentModificationDate == destinationValues.contentModificationDate
    }
}
