import Foundation

public enum DirectoryComparisonStatus: String, Sendable {
    case onlyLeft
    case onlyRight
    case different
    case same
}

public struct DirectoryComparisonEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let relativePath: String
    public let leftURL: URL?
    public let rightURL: URL?
    public let status: DirectoryComparisonStatus

    public init(relativePath: String, leftURL: URL?, rightURL: URL?, status: DirectoryComparisonStatus) {
        self.id = relativePath
        self.relativePath = relativePath
        self.leftURL = leftURL
        self.rightURL = rightURL
        self.status = status
    }
}

public struct DirectoryComparisonService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func compare(left: URL, right: URL, includeHidden: Bool = false) throws -> [DirectoryComparisonEntry] {
        let leftSnapshot = try snapshot(root: left, includeHidden: includeHidden)
        let rightSnapshot = try snapshot(root: right, includeHidden: includeHidden)
        let paths = Set(leftSnapshot.keys).union(rightSnapshot.keys)

        return paths.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .compactMap { path in
                let leftItem = leftSnapshot[path]
                let rightItem = rightSnapshot[path]
                switch (leftItem, rightItem) {
                case let (leftItem?, nil):
                    return DirectoryComparisonEntry(
                        relativePath: path,
                        leftURL: leftItem.url,
                        rightURL: nil,
                        status: .onlyLeft
                    )
                case let (nil, rightItem?):
                    return DirectoryComparisonEntry(
                        relativePath: path,
                        leftURL: nil,
                        rightURL: rightItem.url,
                        status: .onlyRight
                    )
                case let (leftItem?, rightItem?):
                    let status: DirectoryComparisonStatus = leftItem.isSameContent(as: rightItem) ? .same : .different
                    return DirectoryComparisonEntry(
                        relativePath: path,
                        leftURL: leftItem.url,
                        rightURL: rightItem.url,
                        status: status
                    )
                case (nil, nil):
                    return nil
                }
            }
    }

    private func snapshot(root: URL, includeHidden: Bool) throws -> [String: SnapshotItem] {
        let resolvedRootPath = root.resolvingSymlinksInPath().path
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return [:]
        }

        var result: [String: SnapshotItem] = [:]
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            guard includeHidden || values.isHidden != true else { continue }
            let resolvedPath = url.resolvingSymlinksInPath().path
            let relativePath: String
            if resolvedPath.hasPrefix(resolvedRootPath + "/") {
                relativePath = String(resolvedPath.dropFirst(resolvedRootPath.count + 1))
            } else {
                relativePath = url.lastPathComponent
            }
            result[relativePath] = SnapshotItem(
                url: url.standardizedFileURL,
                isDirectory: values.isDirectory == true && values.isSymbolicLink != true,
                size: values.fileSize.map(Int64.init),
                modifiedAt: values.contentModificationDate
            )
        }
        return result
    }

    private struct SnapshotItem {
        let url: URL
        let isDirectory: Bool
        let size: Int64?
        let modifiedAt: Date?

        func isSameContent(as other: SnapshotItem) -> Bool {
            guard isDirectory == other.isDirectory else { return false }
            if isDirectory { return true }
            return size == other.size && modifiedAt == other.modifiedAt
        }
    }
}
