import Foundation

public struct FileSystemService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func contents(
        of directory: URL,
        includeHidden: Bool = false,
        sortRule: FileSortRule = FileSortRule(),
        folderSizeCache: FolderSizeCache? = nil
    ) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .isHiddenKey,
            .localizedNameKey,
            .localizedTypeDescriptionKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: options)
        return try urls.map { try item(for: $0, folderSizeCache: folderSizeCache) }
            .sorted { FileSystemService.sortItems($0, $1, rule: sortRule) }
    }

    public func parent(of url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    public func calculateFolderSize(at folder: URL, cache: FolderSizeCache = FolderSizeCache()) throws -> FolderSizeResolution {
        let modifiedAt = try folder.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cachedSize = cache.size(for: folder, modifiedAt: modifiedAt) {
            return .cached(cachedSize)
        }

        let size = try recursiveSize(of: folder)
        try cache.setSize(size, for: folder, modifiedAt: modifiedAt)
        return .computed(size)
    }

    private func item(for url: URL, folderSizeCache: FolderSizeCache?) throws -> FileItem {
        let itemURL = url.standardizedFileURL
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .isHiddenKey,
            .localizedNameKey,
            .localizedTypeDescriptionKey
        ])
        let kind: FileItemKind
        if values.isAliasFile == true {
            kind = .alias
        } else if values.isPackage == true {
            kind = .package
        } else if values.isDirectory == true {
            kind = .folder
        } else {
            kind = .file
        }
        let size = values.fileSize.map(Int64.init)
            ?? folderSizeCache?.size(for: url, modifiedAt: values.contentModificationDate)
        return FileItem(
            url: itemURL,
            name: values.localizedName ?? itemURL.lastPathComponent,
            kind: kind,
            type: Self.typeDescription(for: itemURL, kind: kind, localizedType: values.localizedTypeDescription),
            size: size,
            modifiedAt: values.contentModificationDate,
            createdAt: values.creationDate,
            isHidden: values.isHidden ?? false
        )
    }

    private func recursiveSize(of folder: URL) throws -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey]
        let options: FileManager.DirectoryEnumerationOptions = []
        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: keys,
            options: options
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            guard values.isSymbolicLink != true else { continue }
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    private static func sortItems(_ left: FileItem, _ right: FileItem, rule: FileSortRule) -> Bool {
        if left.isDirectoryLike != right.isDirectoryLike {
            return left.isDirectoryLike
        }
        let comparison = compare(left, right, field: rule.field)
        if comparison == .orderedSame {
            return left.name.localizedStandardCompare(right.name) == .orderedAscending
        }
        switch rule.direction {
        case .ascending:
            return comparison == .orderedAscending
        case .descending:
            return comparison == .orderedDescending
        }
    }

    private static func compare(_ left: FileItem, _ right: FileItem, field: FileSortField) -> ComparisonResult {
        switch field {
        case .name:
            return left.name.localizedStandardCompare(right.name)
        case .size:
            return compareOptional(left.size, right.size)
        case .modifiedAt:
            return compareOptional(left.modifiedAt, right.modifiedAt)
        case .type:
            return left.type.localizedStandardCompare(right.type)
        }
    }

    private static func compareOptional<T: Comparable>(_ left: T?, _ right: T?) -> ComparisonResult {
        switch (left, right) {
        case let (left?, right?):
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        case (nil, nil):
            return .orderedSame
        case (nil, _?):
            return .orderedDescending
        case (_?, nil):
            return .orderedAscending
        }
    }

    private static func typeDescription(for url: URL, kind: FileItemKind, localizedType: String?) -> String {
        if let localizedType, !localizedType.isEmpty {
            return localizedType
        }
        switch kind {
        case .folder:
            return "Folder"
        case .package:
            return "Package"
        case .alias:
            return "Alias"
        case .file:
            return url.pathExtension.isEmpty ? "File" : url.pathExtension.uppercased()
        case .other:
            return "Other"
        }
    }
}
