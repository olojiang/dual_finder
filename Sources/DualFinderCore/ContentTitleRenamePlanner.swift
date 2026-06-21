import Foundation

public enum ContentTitleRenameError: LocalizedError, Equatable {
    case unsupportedFile(URL)
    case unreadableText(URL)
    case missingTitle(URL)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedFile(url):
            "Cannot extract a filename from \(url.lastPathComponent). Select TXT files."
        case let .unreadableText(url):
            "Could not decode text in \(url.lastPathComponent)."
        case let .missingTitle(url):
            "Could not find a title in \(url.lastPathComponent)."
        }
    }
}

public enum ContentTitleRenameSkipReason: Equatable, Sendable {
    case unsupportedFile
    case unreadableText
    case missingTitle
    case duplicateDestination(URL)
    case destinationExists(URL)
    case unchanged
}

public struct ContentTitleRenameSkippedItem: Equatable, Sendable {
    public let sourceURL: URL
    public let reason: ContentTitleRenameSkipReason

    public init(sourceURL: URL, reason: ContentTitleRenameSkipReason) {
        self.sourceURL = sourceURL
        self.reason = reason
    }
}

public struct ContentTitleRenamePlan: Equatable, Sendable {
    public let operations: [BatchRenameOperation]
    public let skipped: [ContentTitleRenameSkippedItem]

    public init(operations: [BatchRenameOperation], skipped: [ContentTitleRenameSkippedItem]) {
        self.operations = operations
        self.skipped = skipped
    }
}

public struct ContentTitleRenamePlanner {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func plan(for items: [FileItem]) -> ContentTitleRenamePlan {
        let sourcePaths = Set(items.map { $0.url.standardizedFileURL.path })
        var destinationPaths = Set<String>()
        var operations: [BatchRenameOperation] = []
        var skipped: [ContentTitleRenameSkippedItem] = []

        for item in items {
            do {
                let operation = try operation(for: item)
                let source = operation.sourceURL.standardizedFileURL
                let destination = operation.destinationURL.standardizedFileURL

                guard source != destination else {
                    skipped.append(ContentTitleRenameSkippedItem(sourceURL: item.url, reason: .unchanged))
                    continue
                }
                guard destinationPaths.insert(destination.path).inserted else {
                    skipped.append(ContentTitleRenameSkippedItem(
                        sourceURL: item.url,
                        reason: .duplicateDestination(destination)
                    ))
                    continue
                }
                if fileManager.fileExists(atPath: destination.path), !sourcePaths.contains(destination.path) {
                    skipped.append(ContentTitleRenameSkippedItem(
                        sourceURL: item.url,
                        reason: .destinationExists(destination)
                    ))
                    continue
                }

                operations.append(operation)
            } catch let error as ContentTitleRenameError {
                skipped.append(ContentTitleRenameSkippedItem(sourceURL: item.url, reason: skipReason(for: error)))
            } catch {
                skipped.append(ContentTitleRenameSkippedItem(sourceURL: item.url, reason: .unreadableText))
            }
        }

        return ContentTitleRenamePlan(operations: operations, skipped: skipped)
    }

    public func operations(for items: [FileItem]) throws -> [BatchRenameOperation] {
        try items.map { try operation(for: $0) }
    }

    private func operation(for item: FileItem) throws -> BatchRenameOperation {
        guard item.kind == .file,
              item.url.pathExtension.localizedCaseInsensitiveCompare("txt") == .orderedSame else {
            throw ContentTitleRenameError.unsupportedFile(item.url)
        }

        let data = try Data(contentsOf: item.url)
        guard let text = Self.decodeText(data) else {
            throw ContentTitleRenameError.unreadableText(item.url)
        }
        guard let title = Self.firstTitleCandidate(in: text) else {
            throw ContentTitleRenameError.missingTitle(item.url)
        }

        return BatchRenameOperation(
            sourceURL: item.url,
            newName: Self.fileName(from: title, preservingExtensionFrom: item.name)
        )
    }

    private func skipReason(for error: ContentTitleRenameError) -> ContentTitleRenameSkipReason {
        switch error {
        case .unsupportedFile:
            .unsupportedFile
        case .unreadableText:
            .unreadableText
        case .missingTitle:
            .missingTitle
        }
    }

    static func firstTitleCandidate(in text: String) -> String? {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        for rawLine in normalized.split(separator: "\n", omittingEmptySubsequences: false).prefix(80) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !isDecorativeSeparator(line) else { continue }

            let title = sanitizedTitle(strippingMetadata(from: line))
            guard (2...80).contains(title.count), !isNonTitleLine(title) else { continue }
            return title
        }

        return nil
    }

    private static func decodeText(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }

        return EncodingCandidate.legacyCandidates
            .compactMap { candidate -> String? in
                String(data: data, encoding: candidate.encoding)
            }
            .max { score($0) < score($1) }
    }

    private static func score(_ text: String) -> Int {
        let chineseCount = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        let replacementPenalty = text.unicodeScalars.filter { $0.value == 0xFFFD }.count * 10_000
        return chineseCount - replacementPenalty
    }

    private static func strippingMetadata(from line: String) -> String {
        var candidate = line
            .replacingOccurrences(of: "\u{feff}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        while true {
            let before = candidate
            candidate = candidate.replacingOccurrences(
                of: #"^\[?\d{4}[-./年]\d{1,2}[-./月]\d{1,2}日?\]?\s*"#,
                with: "",
                options: .regularExpression
            )
            candidate = candidate.replacingOccurrences(
                of: #"^\s*(\[[^\]\n]{1,16}\]|【[^】\n]{1,16}】|\([^\)\n]{1,16}\)|（[^）\n]{1,16}）)\s*"#,
                with: "",
                options: .regularExpression
            )
            candidate = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate == before { return candidate }
        }
    }

    private static func sanitizedTitle(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        let replacedScalars = title.unicodeScalars.map { scalar -> String in
            invalidCharacters.contains(scalar) ? " " : String(scalar)
        }
        let collapsedWhitespace = replacedScalars
            .joined()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return String(collapsedWhitespace.prefix(128))
    }

    private static func isDecorativeSeparator(_ line: String) -> Bool {
        let decorative = CharacterSet(charactersIn: "-_=*~·•—")
        let scalars = line.unicodeScalars.filter { !$0.properties.isWhitespace }
        return !scalars.isEmpty && scalars.allSatisfy { decorative.contains($0) }
    }

    private static func isNonTitleLine(_ line: String) -> Bool {
        let compact = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
            .uppercased()

        if compact == "目录" || compact == "目錄" || compact == "CONTENTS" || compact == "TABLEOFCONTENTS" {
            return true
        }
        if compact.range(of: #"^(CHAPTER|CH|第)[0-9０-９一二三四五六七八九十百千万兩两零〇]+[章节篇回卷部集]?$"#, options: .regularExpression) != nil {
            return true
        }
        if ["发信人", "發信人", "信人", "作者", "标题", "標題", "女主角", "男主角"].contains(where: compact.hasPrefix) {
            return true
        }
        if compact.range(of: #"^(以下|本文|本故事|文章内容|警告|声明|申明)"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private static func fileName(from title: String, preservingExtensionFrom originalName: String) -> String {
        let ext = FileNameUtilities.extensionName(for: originalName)
        guard !ext.isEmpty else { return title }
        if FileNameUtilities.extensionName(for: title).localizedCaseInsensitiveCompare(ext) == .orderedSame {
            return title
        }
        return "\(title).\(ext)"
    }
}

private struct EncodingCandidate {
    let label: String
    let encoding: String.Encoding

    static let legacyCandidates: [EncodingCandidate] = [
        candidate(label: "gbk", ianaName: "GBK"),
        candidate(label: "gb2312", ianaName: "GB2312"),
        candidate(label: "gb18030", ianaName: "GB18030"),
        candidate(label: "big5", ianaName: "Big5"),
        candidate(label: "shift_jis", ianaName: "Shift_JIS"),
        candidate(label: "euc-kr", ianaName: "EUC-KR"),
        EncodingCandidate(label: "windows-1252", encoding: .windowsCP1252),
        EncodingCandidate(label: "iso-8859-1", encoding: .isoLatin1)
    ].compactMap { $0 }

    private static func candidate(label: String, ianaName: String) -> EncodingCandidate? {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(ianaName as CFString)
        guard cfEncoding != kCFStringEncodingInvalidId else { return nil }
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        guard nsEncoding != UInt(kCFStringEncodingInvalidId) else { return nil }
        return EncodingCandidate(label: label, encoding: String.Encoding(rawValue: nsEncoding))
    }
}
