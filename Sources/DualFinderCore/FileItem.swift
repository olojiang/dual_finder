import Foundation

public enum FileItemKind: String, Sendable {
    case folder
    case file
    case package
    case alias
    case other
}

public struct FileItem: Identifiable, Hashable, Sendable {
    public let id: URL
    public let url: URL
    public let name: String
    public let kind: FileItemKind
    public let size: Int64?
    public let modifiedAt: Date?
    public let isHidden: Bool

    public init(url: URL, name: String, kind: FileItemKind, size: Int64?, modifiedAt: Date?, isHidden: Bool) {
        self.id = url
        self.url = url
        self.name = name
        self.kind = kind
        self.size = size
        self.modifiedAt = modifiedAt
        self.isHidden = isHidden
    }

    public var isDirectoryLike: Bool {
        kind == .folder || kind == .package
    }
}
