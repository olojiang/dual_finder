import Foundation

public enum BatchRenameError: LocalizedError, Equatable {
    case invalidRegularExpression(String)
    case emptyName(URL)
    case invalidName(String)
    case duplicateDestination(URL)
    case destinationExists(URL)

    public var errorDescription: String? {
        switch self {
        case let .invalidRegularExpression(message):
            "Invalid regular expression: \(message)"
        case let .emptyName(url):
            "Generated name is empty for \(url.lastPathComponent)."
        case let .invalidName(name):
            "Generated name is not a valid file name: \(name)"
        case let .duplicateDestination(url):
            "Multiple items would be renamed to \(url.lastPathComponent)."
        case let .destinationExists(url):
            "Destination already exists: \(url.lastPathComponent)."
        }
    }
}

public enum BatchRenamePreviewStatus: Equatable, Sendable {
    case unchanged
    case ready
    case emptyName
    case invalidName
    case duplicateDestination
    case destinationExists

    public var allowsApply: Bool {
        switch self {
        case .unchanged, .ready:
            true
        case .emptyName, .invalidName, .duplicateDestination, .destinationExists:
            false
        }
    }
}

public struct BatchRenamePreview: Identifiable, Equatable, Sendable {
    public let id: URL
    public let sourceURL: URL
    public let originalName: String
    public let newName: String
    public let destinationURL: URL
    public let status: BatchRenamePreviewStatus

    public init(
        sourceURL: URL,
        originalName: String,
        newName: String,
        destinationURL: URL,
        status: BatchRenamePreviewStatus
    ) {
        self.id = sourceURL
        self.sourceURL = sourceURL
        self.originalName = originalName
        self.newName = newName
        self.destinationURL = destinationURL
        self.status = status
    }

    public var isChanged: Bool {
        sourceURL.standardizedFileURL != destinationURL.standardizedFileURL
    }
}

public struct BatchRenameOperation: Equatable, Sendable {
    public let sourceURL: URL
    public let newName: String

    public init(sourceURL: URL, newName: String) {
        self.sourceURL = sourceURL
        self.newName = newName
    }

    public var destinationURL: URL {
        sourceURL.deletingLastPathComponent().appendingPathComponent(newName).standardizedFileURL
    }
}

public enum BatchRenameRule: Equatable, Sendable {
    case numbering(prefix: String, suffix: String, start: Int, padding: Int, includeOriginalName: Bool)
    case literalReplace(search: String, replacement: String, caseSensitive: Bool)
    case regularExpression(pattern: String, replacement: String)
    case changeExtension(String)
    case metadataTemplate(String)
}

public struct BatchRenamePlanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func previews(for items: [FileItem], rule: BatchRenameRule) throws -> [BatchRenamePreview] {
        let rawPreviews = try items.enumerated().map { offset, item in
            let newName = try generatedName(for: item, offset: offset, rule: rule)
            let destination = item.url.deletingLastPathComponent().appendingPathComponent(newName).standardizedFileURL
            return BatchRenamePreview(
                sourceURL: item.url,
                originalName: item.name,
                newName: newName,
                destinationURL: destination,
                status: initialStatus(for: item.url, destination: destination, newName: newName)
            )
        }

        return previewsWithCollisionStatus(rawPreviews)
    }

    private func generatedName(for item: FileItem, offset: Int, rule: BatchRenameRule) throws -> String {
        switch rule {
        case let .numbering(prefix, suffix, start, padding, includeOriginalName):
            let number = paddedNumber(start + offset, padding: padding)
            let base = FileNameUtilities.baseName(for: item.name)
            let ext = FileNameUtilities.extensionWithDot(for: item.name)
            if includeOriginalName {
                return "\(prefix)\(number)_\(base)\(suffix)\(ext)"
            }
            return "\(prefix)\(number)\(suffix)\(ext)"

        case let .literalReplace(search, replacement, caseSensitive):
            guard !search.isEmpty else { return item.name }
            let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
            return item.name.replacingOccurrences(of: search, with: replacement, options: options)

        case let .regularExpression(pattern, replacement):
            guard !pattern.isEmpty else { return item.name }
            do {
                let regex = try NSRegularExpression(pattern: pattern)
                let range = NSRange(item.name.startIndex..<item.name.endIndex, in: item.name)
                return regex.stringByReplacingMatches(in: item.name, range: range, withTemplate: replacement)
            } catch {
                throw BatchRenameError.invalidRegularExpression(error.localizedDescription)
            }

        case let .changeExtension(newExtension):
            let normalizedExtension = FileNameUtilities.normalizedExtension(newExtension)
            let base = FileNameUtilities.baseName(for: item.name)
            return normalizedExtension.isEmpty ? base : "\(base).\(normalizedExtension)"

        case let .metadataTemplate(template):
            return render(template: template, item: item, offset: offset)
        }
    }

    private func initialStatus(for source: URL, destination: URL, newName: String) -> BatchRenamePreviewStatus {
        guard !FileNameUtilities.isBlank(newName) else { return .emptyName }
        guard !FileNameUtilities.containsInvalidPathComponentCharacters(newName) else { return .invalidName }

        return source.standardizedFileURL == destination.standardizedFileURL ? .unchanged : .ready
    }

    private func previewsWithCollisionStatus(_ previews: [BatchRenamePreview]) -> [BatchRenamePreview] {
        let changedSources = Set(previews.filter(\.isChanged).map { $0.sourceURL.standardizedFileURL.path })
        let destinationCounts = Dictionary(grouping: previews.filter(\.isChanged), by: { $0.destinationURL.path })
            .mapValues(\.count)

        return previews.map { preview in
            guard preview.status.allowsApply, preview.isChanged else { return preview }

            if destinationCounts[preview.destinationURL.path, default: 0] > 1 {
                return preview.replacingStatus(.duplicateDestination)
            }

            if fileManager.fileExists(atPath: preview.destinationURL.path),
               !changedSources.contains(preview.destinationURL.path) {
                return preview.replacingStatus(.destinationExists)
            }

            return preview
        }
    }

    private func render(template: String, item: FileItem, offset: Int) -> String {
        let replacements = [
            "{index}": String(offset + 1),
            "{name}": item.name,
            "{base}": FileNameUtilities.baseName(for: item.name),
            "{ext}": FileNameUtilities.extensionName(for: item.name),
            "{extWithDot}": FileNameUtilities.extensionWithDot(for: item.name),
            "{date}": formattedDate(item.modifiedAt),
            "{time}": formattedTime(item.modifiedAt),
            "{modifiedDate}": formattedDate(item.modifiedAt),
            "{modifiedTime}": formattedTime(item.modifiedAt),
            "{createdDate}": formattedDate(item.createdAt),
            "{createdTime}": formattedTime(item.createdAt),
            "{size}": item.size.map(String.init) ?? "",
            "{type}": item.type,
            "{kind}": item.kind.rawValue
        ]

        return replacements.reduce(template) { rendered, pair in
            rendered.replacingOccurrences(of: pair.key, with: pair.value)
        }
    }

    private func paddedNumber(_ value: Int, padding: Int) -> String {
        let width = max(0, padding)
        guard width > 0 else { return String(value) }
        return String(format: "%0\(width)d", value)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func formattedTime(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH-mm-ss"
        return formatter.string(from: date)
    }
}

private extension BatchRenamePreview {
    func replacingStatus(_ status: BatchRenamePreviewStatus) -> BatchRenamePreview {
        BatchRenamePreview(
            sourceURL: sourceURL,
            originalName: originalName,
            newName: newName,
            destinationURL: destinationURL,
            status: status
        )
    }
}
