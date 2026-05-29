import Foundation

public enum FileOperationError: LocalizedError, Equatable {
    case trashUnsupported
    case emptyName

    public var errorDescription: String? {
        switch self {
        case .trashUnsupported:
            "Moving files to Trash is only supported on macOS."
        case .emptyName:
            "Name cannot be empty."
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

    public func copy(_ sources: [URL], to destinationDirectory: URL) throws {
        logger?.info("file-operation", "copy.started", metadata: operationMetadata(sources, destinationDirectory))
        for source in sources {
            let destination = uniqueDestination(for: source.lastPathComponent, in: destinationDirectory)
            try fileManager.copyItem(at: source, to: destination)
            logger?.info("file-operation", "copy.item.completed", metadata: [
                "source": source.path,
                "destination": destination.path
            ])
        }
        logger?.info("file-operation", "copy.completed", metadata: operationMetadata(sources, destinationDirectory))
    }

    public func move(_ sources: [URL], to destinationDirectory: URL) throws {
        logger?.info("file-operation", "move.started", metadata: operationMetadata(sources, destinationDirectory))
        for source in sources {
            let destination = uniqueDestination(for: source.lastPathComponent, in: destinationDirectory)
            try fileManager.moveItem(at: source, to: destination)
            logger?.info("file-operation", "move.item.completed", metadata: [
                "source": source.path,
                "destination": destination.path
            ])
        }
        logger?.info("file-operation", "move.completed", metadata: operationMetadata(sources, destinationDirectory))
    }

    public func createFolder(named name: String, in directory: URL) throws -> URL {
        let destination = uniqueDestination(for: name, in: directory)
        try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
        logger?.info("file-operation", "folder.created", metadata: ["path": destination.path])
        return destination.standardizedFileURL
    }

    public func rename(_ source: URL, to newName: String) throws -> URL {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
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

    public func trash(_ sources: [URL]) throws {
        logger?.info("file-operation", "trash.started", metadata: ["count": "\(sources.count)"])
        for source in sources {
            #if os(macOS)
            try fileManager.trashItem(at: source, resultingItemURL: nil)
            #else
            throw FileOperationError.trashUnsupported
            #endif
            logger?.warning("file-operation", "trash.item.completed", metadata: ["source": source.path])
        }
        logger?.info("file-operation", "trash.completed", metadata: ["count": "\(sources.count)"])
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

        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var index = 2
        while fileManager.fileExists(atPath: destination.path) {
            let candidate = ext.isEmpty ? "\(base) \(index)" : "\(base) \(index).\(ext)"
            destination = directory.appendingPathComponent(candidate)
            index += 1
        }
        return destination
    }

    private func validatedBatchRenameChanges(_ operations: [BatchRenameOperation]) throws -> [(source: URL, destination: URL)] {
        var destinationPaths = Set<String>()
        let changes = try operations.compactMap { operation -> (source: URL, destination: URL)? in
            let newName = operation.newName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !newName.isEmpty else {
                throw BatchRenameError.emptyName(operation.sourceURL)
            }
            guard newName.rangeOfCharacter(from: CharacterSet(charactersIn: "/:")) == nil else {
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
}
