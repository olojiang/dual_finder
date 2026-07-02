import Foundation

public enum PathWithSizeClipboardFormat {
    public static func absolutePath(for url: URL) -> String {
        if let android = AndroidFileURL.parse(url) {
            return "\(android.deviceSerial):\(android.path)"
        }
        return url.standardizedFileURL.path
    }

    public static func resolveByteSize(
        for url: URL,
        cachedItemSize: Int64?,
        isDirectoryLike: Bool?,
        fileSystemService: FileSystemService,
        folderSizeCache: FolderSizeCache
    ) throws -> Int64? {
        if let cachedItemSize {
            return cachedItemSize
        }

        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .fileSizeKey])
        let directoryLike = isDirectoryLike == true
            || values.isDirectory == true
            || values.isPackage == true
        if directoryLike {
            return try fileSystemService.calculateFolderSize(at: url, cache: folderSizeCache).size
        }
        if let fileSize = values.fileSize {
            return Int64(fileSize)
        }
        return nil
    }

    public static func compactSize(_ size: Int64) -> String {
        guard size >= 1_000 else {
            return "\(size)b"
        }

        let units = ["k", "m", "g", "t", "p"]
        var value = Double(size)
        var unitIndex = -1
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        return String(format: "%.3f%@", locale: Locale(identifier: "en_US_POSIX"), value, units[unitIndex])
    }

    public static func line(path: String, size: Int64?) -> String {
        let sizeText = size.map(compactSize) ?? "--"
        return "\(path) \(sizeText)"
    }
}
