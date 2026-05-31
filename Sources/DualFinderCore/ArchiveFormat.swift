import Foundation

/// Supported archive container formats for extract; compress currently targets ZIP only.
public enum ArchiveFormat: String, Sendable, Equatable, CaseIterable {
    case zip
    case tar
    case tarGzip
    case tarBzip2
    case tarXz
    case gzip
    case bzip2
    case xz
    case sevenZip
    case rar
    case iso
}

public enum ArchiveFormatDetector {
    private static let extractSuffixes: [(suffix: String, format: ArchiveFormat)] = [
        (".tar.gz", .tarGzip),
        (".tgz", .tarGzip),
        (".tar.bz2", .tarBzip2),
        (".tbz2", .tarBzip2),
        (".tar.xz", .tarXz),
        (".txz", .tarXz),
        (".tar", .tar),
        (".zip", .zip),
        (".7z", .sevenZip),
        (".rar", .rar),
        (".iso", .iso),
        (".gz", .gzip),
        (".bz2", .bzip2),
        (".xz", .xz)
    ]

    public static func format(for url: URL) -> ArchiveFormat? {
        let name = url.lastPathComponent.lowercased()
        guard !name.isEmpty else { return nil }
        for entry in extractSuffixes {
            if name.hasSuffix(entry.suffix) {
                if entry.suffix == ".gz", name.hasSuffix(".tar.gz") { continue }
                if entry.suffix == ".bz2", name.hasSuffix(".tar.bz2") { continue }
                if entry.suffix == ".xz", name.hasSuffix(".tar.xz") { continue }
                return entry.format
            }
        }
        return nil
    }

    public static func isExtractable(_ url: URL) -> Bool {
        format(for: url) != nil
    }

    /// Base name used for a WinRAR-style subfolder (strips compound archive extensions).
    public static func extractionFolderName(for url: URL) -> String {
        var name = url.lastPathComponent
        let compoundSuffixes = [".tar.gz", ".tar.bz2", ".tar.xz", ".tgz", ".tbz2", ".txz"]
        for suffix in compoundSuffixes {
            if name.lowercased().hasSuffix(suffix) {
                name = String(name.dropLast(suffix.count))
                return name
            }
        }
        return FileNameUtilities.baseName(for: name)
    }
}
