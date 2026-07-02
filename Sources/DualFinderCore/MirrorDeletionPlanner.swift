import Foundation

public struct MirrorDeletionSummary: Equatable, Sendable {
    public let itemCount: Int
    public let totalByteCount: Int64

    public init(itemCount: Int, totalByteCount: Int64) {
        self.itemCount = itemCount
        self.totalByteCount = totalByteCount
    }

    public var isEmpty: Bool {
        itemCount == 0
    }
}

public enum MirrorDeletionPlanner {
    public static func destinationRoot(for source: URL, in destinationDirectory: URL) -> URL {
        destinationDirectory.appendingPathComponent(source.lastPathComponent)
    }

    public static func deletionSummary(
        sources: [URL],
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> MirrorDeletionSummary {
        let extras = try extrasToDelete(
            sources: sources,
            destinationDirectory: destinationDirectory,
            fileManager: fileManager
        )
        var totalByteCount: Int64 = 0
        for url in extras {
            totalByteCount += try byteCount(of: url, fileManager: fileManager)
        }
        return MirrorDeletionSummary(itemCount: extras.count, totalByteCount: totalByteCount)
    }

    public static func extrasToDelete(
        sources: [URL],
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> [URL] {
        var extras: [URL] = []
        for source in sources {
            let sourcePaths = try relativePaths(in: source, fileManager: fileManager)
            let destinationRoot = destinationRoot(for: source, in: destinationDirectory)
            extras.append(contentsOf: try extraItems(
                at: destinationRoot,
                sourcePaths: sourcePaths,
                relativePrefix: "",
                fileManager: fileManager
            ))
        }
        return extras.sorted { $0.path.count > $1.path.count }
    }

    private static func relativePaths(in sourceRoot: URL, fileManager: FileManager) throws -> Set<String> {
        var paths: Set<String> = []
        try collectSourcePaths(at: sourceRoot, relativePrefix: "", into: &paths, fileManager: fileManager)
        return paths
    }

    private static func collectSourcePaths(
        at url: URL,
        relativePrefix: String,
        into paths: inout Set<String>,
        fileManager: FileManager
    ) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
        if values.isRegularFile == true || values.isSymbolicLink == true {
            if relativePrefix.isEmpty {
                paths.insert(url.lastPathComponent)
            } else {
                paths.insert(relativePrefix)
            }
            return
        }

        guard values.isDirectory == true else { return }

        if !relativePrefix.isEmpty {
            paths.insert(relativePrefix)
        }

        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )
        for child in children {
            let childName = child.lastPathComponent
            let childRelative = relativePrefix.isEmpty ? childName : "\(relativePrefix)/\(childName)"
            try collectSourcePaths(
                at: child,
                relativePrefix: childRelative,
                into: &paths,
                fileManager: fileManager
            )
        }
    }

    private static func extraItems(
        at destinationRoot: URL,
        sourcePaths: Set<String>,
        relativePrefix: String,
        fileManager: FileManager
    ) throws -> [URL] {
        guard fileManager.fileExists(atPath: destinationRoot.path) else { return [] }

        let rootValues = try destinationRoot.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard rootValues.isDirectory == true, rootValues.isSymbolicLink != true else { return [] }

        let children = try fileManager.contentsOfDirectory(
            at: destinationRoot,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        )

        var result: [URL] = []
        for child in children {
            let childName = child.lastPathComponent
            let childRelative = relativePrefix.isEmpty ? childName : "\(relativePrefix)/\(childName)"
            if !sourcePaths.contains(childRelative) {
                result.append(child)
                continue
            }

            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values.isDirectory == true && values.isSymbolicLink != true {
                result.append(contentsOf: try extraItems(
                    at: child,
                    sourcePaths: sourcePaths,
                    relativePrefix: childRelative,
                    fileManager: fileManager
                ))
            }
        }
        return result
    }

    private static func byteCount(of url: URL, fileManager: FileManager) throws -> Int64 {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        if values.isRegularFile == true || values.isSymbolicLink == true {
            return Int64(values.fileSize ?? 0)
        }
        guard values.isDirectory == true else { return 0 }

        let children = try fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey],
            options: []
        )
        return try children.reduce(Int64(0)) { partial, child in
            partial + (try byteCount(of: child, fileManager: fileManager))
        }
    }
}
