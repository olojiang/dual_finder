import Foundation
#if canImport(AppKit)
import AppKit
#endif

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

    public func trash(_ sources: [URL]) throws {
        logger?.info("file-operation", "trash.started", metadata: ["count": "\(sources.count)"])
        for source in sources {
            #if canImport(AppKit)
            try FileManager.default.trashItem(at: source, resultingItemURL: nil)
            #else
            try fileManager.removeItem(at: source)
            #endif
            logger?.warning("file-operation", "trash.item.completed", metadata: ["source": source.path])
        }
        logger?.info("file-operation", "trash.completed", metadata: ["count": "\(sources.count)"])
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
