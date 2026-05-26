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
        return destination
    }

    public func rename(_ source: URL, to newName: String) throws -> URL {
        guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw FileOperationError.emptyName
        }

        let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
        guard destination != source else {
            return source
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
        return destination
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

    private func operationMetadata(_ sources: [URL], _ destination: URL) -> [String: String] {
        [
            "count": "\(sources.count)",
            "destination": destination.path,
            "sources": sources.map(\.path).joined(separator: "|")
        ]
    }
}
