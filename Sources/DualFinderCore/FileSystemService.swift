import Foundation

public struct FileSystemService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func contents(of directory: URL, includeHidden: Bool = false) throws -> [FileItem] {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isPackageKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .localizedNameKey
        ]
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let urls = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys), options: options)
        return try urls.map(item(for:)).sorted(by: FileSystemService.sortItems)
    }

    public func parent(of url: URL) -> URL? {
        let parent = url.deletingLastPathComponent()
        return parent.path == url.path ? nil : parent
    }

    private func item(for url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isPackageKey,
            .isAliasFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
            .isHiddenKey,
            .localizedNameKey
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
        return FileItem(
            url: url,
            name: values.localizedName ?? url.lastPathComponent,
            kind: kind,
            size: values.fileSize.map(Int64.init),
            modifiedAt: values.contentModificationDate,
            isHidden: values.isHidden ?? false
        )
    }

    private static func sortItems(_ left: FileItem, _ right: FileItem) -> Bool {
        if left.isDirectoryLike != right.isDirectoryLike {
            return left.isDirectoryLike
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }
}
