import Foundation

public enum FileOperationError: LocalizedError, Equatable {
    case trashUnsupported
    case emptyName
    case cancelled
    case invalidDestination

    public var errorDescription: String? {
        switch self {
        case .trashUnsupported:
            "Moving files to Trash is only supported on macOS."
        case .emptyName:
            "Name cannot be empty."
        case .cancelled:
            "Operation cancelled."
        case .invalidDestination:
            "Destination cannot be the source item or one of its children."
        }
    }
}

public struct FileOperationService {
    private let fileManager: FileManager
    private let logger: AppLogging?

    public init(fileManager: FileManager = .default, logger: AppLogging?) {
        self.fileManager = fileManager
        self.logger = logger
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
        let context = try OperationContext(
            sources: sources,
            destinationDirectory: destinationDirectory,
            fileManager: fileManager,
            cancellation: cancellation,
            progress: progress
        )
        try copySources(
            sources,
            to: destinationDirectory,
            options: options,
            context: context,
            conflictResolver: conflictResolver
        )
        logger?.info("file-operation", "copy.completed", metadata: operationMetadata(sources, destinationDirectory))
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
        let context = try OperationContext(
            sources: sources,
            destinationDirectory: destinationDirectory,
            fileManager: fileManager,
            cancellation: cancellation,
            progress: progress
        )
        var copiedRoots: [CopiedRoot] = []
        do {
            copiedRoots = try copySources(
                sources,
                to: destinationDirectory,
                options: options,
                context: context,
                conflictResolver: conflictResolver
            )
            for copiedRoot in copiedRoots {
                try context.checkCancellation()
                if fileManager.fileExists(atPath: copiedRoot.source.path) {
                    try fileManager.removeItem(at: copiedRoot.source)
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

        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        let standardizedSource = source.standardizedFileURL
        let standardizedDestination = destination.standardizedFileURL
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

    public func trash(
        _ sources: [URL],
        cancellation: FileOperationCancellation? = nil,
        progress: ((FileOperationProgress) -> Void)? = nil
    ) throws {
        logger?.info("file-operation", "trash.started", metadata: ["count": "\(sources.count)"])
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
                currentItem: source
            ))
            logger?.warning("file-operation", "trash.item.completed", metadata: ["source": source.path])
        }
        logger?.info("file-operation", "trash.completed", metadata: ["count": "\(sources.count)"])
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
            let destination = try resolvedDestination(
                for: source,
                requestedDestination: destinationDirectory.appendingPathComponent(source.lastPathComponent),
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
            copiedRoots.append(CopiedRoot(source: source, destination: destination))
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
            try context.finishItem(source)
        }
    }

    private func copyRegularFile(at source: URL, to destination: URL, context: OperationContext) throws {
        try context.checkCancellation()
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        fileManager.createFile(atPath: destination.path, contents: nil)

        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer {
            try? input.close()
            try? output.close()
        }

        while true {
            try context.checkCancellation()
            let data = try input.read(upToCount: 1024 * 1024) ?? Data()
            guard !data.isEmpty else { break }
            try output.write(contentsOf: data)
            context.advance(bytes: Int64(data.count), currentItem: source)
        }
        try context.finishItem(source)
    }

    private func resolvedDestination(
        for source: URL,
        requestedDestination: URL,
        options: FileOperationOptions,
        conflictResolver: ((FileOperationConflict) -> FileOperationConflictResolution)?
    ) throws -> URL? {
        let conflict = FileOperationConflict(source: source, destination: requestedDestination)
        let resolution = Self.resolvedStrategy(
            for: conflict,
            options: options,
            conflictResolver: conflictResolver
        )

        guard source.standardizedFileURL != requestedDestination.standardizedFileURL else {
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

        switch resolution {
        case .overwrite:
            try fileManager.removeItem(at: requestedDestination)
            return requestedDestination
        case .skip:
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

    public func emptyTrash(at trashDirectory: URL = .trashDirectory) throws -> Int {
        let trashedItems = try fileManager.contentsOfDirectory(
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
        private let totalBytes: Int64
        private let totalItems: Int
        private var completedBytes: Int64 = 0
        private var completedItems: Int = 0

        init(
            sources: [URL],
            destinationDirectory: URL,
            fileManager: FileManager,
            cancellation: FileOperationCancellation?,
            progress: ((FileOperationProgress) -> Void)?
        ) throws {
            self.cancellation = cancellation
            self.progress = progress
            var plan = OperationPlan()
            for source in sources {
                try Self.scan(source, fileManager: fileManager, plan: &plan)
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
            publish(currentItem: currentItem)
        }

        func finishItem(_ currentItem: URL?) throws {
            try checkCancellation()
            completedItems += 1
            publish(currentItem: currentItem)
        }

        private func publish(currentItem: URL?) {
            progress?(FileOperationProgress(
                completedBytes: completedBytes,
                totalBytes: totalBytes,
                completedItems: completedItems,
                totalItems: totalItems,
                currentItem: currentItem
            ))
        }

        private static func scan(_ url: URL, fileManager: FileManager, plan: inout OperationPlan) throws {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            plan.totalItems += 1
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
                try scan(child, fileManager: fileManager, plan: &plan)
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
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }
}
