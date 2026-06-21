import Foundation

public enum TextFileSplitError: LocalizedError, Equatable {
    case unsupportedFile
    case unreadableText
    case notEnoughChapters

    public var errorDescription: String? {
        switch self {
        case .unsupportedFile:
            "Select one TXT file to split."
        case .unreadableText:
            "The selected file could not be decoded as text."
        case .notEnoughChapters:
            "Could not find multiple chapter headings to split."
        }
    }
}

public struct TextFileSplitChapterPreview: Identifiable, Equatable {
    public let id: UUID
    public let heading: String
    public let outputURL: URL
    public let lineNumber: Int
    public let content: String

    public init(id: UUID = UUID(), heading: String, outputURL: URL, lineNumber: Int, content: String) {
        self.id = id
        self.heading = heading
        self.outputURL = outputURL
        self.lineNumber = lineNumber
        self.content = content
    }

    public var outputFileName: String {
        outputURL.lastPathComponent
    }
}

public struct TextFileSplitPreview: Equatable {
    public let sourceURL: URL
    public let detectedEncoding: String
    public let chapters: [TextFileSplitChapterPreview]

    public init(sourceURL: URL, detectedEncoding: String, chapters: [TextFileSplitChapterPreview]) {
        self.sourceURL = sourceURL
        self.detectedEncoding = detectedEncoding
        self.chapters = chapters
    }
}

public struct TextFileSplitService {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public static func canSplit(_ urls: [URL]) -> Bool {
        guard urls.count == 1, let url = urls.first else { return false }
        return url.pathExtension.localizedCaseInsensitiveCompare("txt") == .orderedSame
    }

    public func previewSplit(for sourceURL: URL) throws -> TextFileSplitPreview {
        guard Self.canSplit([sourceURL]) else {
            throw TextFileSplitError.unsupportedFile
        }

        let values = try sourceURL.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw TextFileSplitError.unsupportedFile
        }

        let data = try Data(contentsOf: sourceURL)
        guard let decoded = decodeText(data) else {
            throw TextFileSplitError.unreadableText
        }

        let text = normalizeLineEndings(decoded.text)
        let headings = chapterHeadings(in: text)
        let bodyHeadings: [ChapterHeading]
        if headings.count >= 2 {
            let bodyStartIndex = bodyStartHeadingIndex(in: headings, text: text)
            let chapterBodyHeadings = topLevelHeadings(Array(headings[bodyStartIndex...]))
            bodyHeadings = chapterBodyHeadings.count >= 2 ? chapterBodyHeadings : standaloneArticleHeadings(in: text)
        } else {
            bodyHeadings = standaloneArticleHeadings(in: text)
        }
        guard bodyHeadings.count >= 2 else {
            throw TextFileSplitError.notEnoughChapters
        }

        var reservedOutputNames = Set<String>()
        let chapters = bodyHeadings.enumerated().map { index, heading in
            let end = index + 1 < bodyHeadings.count ? bodyHeadings[index + 1].range.lowerBound : text.endIndex
            let content = String(text[heading.range.lowerBound..<end]).trimmingCharacters(in: .newlines)
            let outputURL = uniqueOutputURL(
                for: heading.title,
                sourceURL: sourceURL,
                reservedNames: reservedOutputNames
            )
            reservedOutputNames.insert(outputURL.lastPathComponent)
            return TextFileSplitChapterPreview(
                heading: heading.title,
                outputURL: outputURL,
                lineNumber: heading.lineNumber,
                content: content + "\n"
            )
        }

        return TextFileSplitPreview(
            sourceURL: sourceURL.standardizedFileURL,
            detectedEncoding: decoded.label,
            chapters: chapters
        )
    }

    @discardableResult
    public func split(_ preview: TextFileSplitPreview, deleteOriginal: Bool = true) throws -> [URL] {
        guard preview.chapters.count >= 2 else {
            throw TextFileSplitError.notEnoughChapters
        }

        var created: [URL] = []
        do {
            for chapter in preview.chapters {
                try chapter.content.write(to: chapter.outputURL, atomically: true, encoding: .utf8)
                created.append(chapter.outputURL.standardizedFileURL)
            }

            if deleteOriginal, fileManager.fileExists(atPath: preview.sourceURL.path) {
                try fileManager.removeItem(at: preview.sourceURL)
            }
            return created
        } catch {
            for url in created where fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
            throw error
        }
    }

    private func decodeText(_ data: Data) -> DecodedText? {
        if let utf8 = String(data: data, encoding: .utf8) {
            return DecodedText(label: "utf-8", text: utf8)
        }

        return EncodingCandidate.legacyCandidates
            .compactMap { candidate -> DecodedText? in
                guard let text = String(data: data, encoding: candidate.encoding) else { return nil }
                return DecodedText(label: candidate.label, text: text)
            }
            .max { score($0.text) < score($1.text) }
    }

    private func score(_ text: String) -> Int {
        let headingBonus = chapterHeadings(in: normalizeLineEndings(text)).count * 1_000
        let chineseCount = text.unicodeScalars.filter {
            (0x4E00...0x9FFF).contains(Int($0.value))
        }.count
        let replacementPenalty = text.unicodeScalars.filter { $0.value == 0xFFFD }.count * 10_000
        return headingBonus + chineseCount - replacementPenalty
    }

    private func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    private func chapterHeadings(in text: String) -> [ChapterHeading] {
        var headings: [ChapterHeading] = []
        var lineStart = text.startIndex
        var lineNumber = 1

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])
            if let parsed = parseHeading(line) {
                headings.append(ChapterHeading(
                    title: parsed.title,
                    ordinal: parsed.ordinal,
                    unit: parsed.unit,
                    unitIndex: parsed.unitIndex,
                    lineNumber: lineNumber,
                    range: lineStart..<lineEnd
                ))
            }

            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
            lineNumber += 1
        }

        return headings
    }

    private func standaloneArticleHeadings(in text: String) -> [ChapterHeading] {
        let lines = indexedLines(in: text)
        var headings: [ChapterHeading] = []

        for index in lines.indices {
            let line = lines[index]
            guard isStandaloneArticleTitle(line.trimmed) else { continue }

            let previousIsBlank = index == lines.startIndex || lines[lines.index(before: index)].trimmed.isEmpty
            let nextIsBlank = index == lines.index(before: lines.endIndex) || lines[lines.index(after: index)].trimmed.isEmpty
            guard previousIsBlank, nextIsBlank else { continue }

            headings.append(ChapterHeading(
                title: line.trimmed,
                ordinal: nil,
                unit: nil,
                unitIndex: nil,
                lineNumber: line.lineNumber,
                range: line.range
            ))
        }

        return headings
    }

    private func indexedLines(in text: String) -> [IndexedLine] {
        var lines: [IndexedLine] = []
        var lineStart = text.startIndex
        var lineNumber = 1

        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = String(text[lineStart..<lineEnd])
            lines.append(IndexedLine(
                trimmed: line.trimmingCharacters(in: .whitespacesAndNewlines),
                lineNumber: lineNumber,
                range: lineStart..<lineEnd
            ))

            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
            lineNumber += 1
        }

        return lines
    }

    private func isStandaloneArticleTitle(_ title: String) -> Bool {
        guard (2...48).contains(title.count),
              !isDecorativeCollectionTitle(title),
              !startsWithParenthesizedSectionMarker(title),
              !startsWithListMarker(title),
              !isDateLikeLine(title) else {
            return false
        }

        let prosePunctuation = CharacterSet(charactersIn: "。！？!?；;，,")
        if title.rangeOfCharacter(from: prosePunctuation) != nil {
            return false
        }
        if let last = title.last, "…~～".contains(last) {
            return false
        }

        return true
    }

    private func isDecorativeCollectionTitle(_ title: String) -> Bool {
        (title.hasPrefix("【") && title.hasSuffix("】"))
            || (title.hasPrefix("《") && title.hasSuffix("》"))
    }

    private func startsWithParenthesizedSectionMarker(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let pairs: [(Character, Character)] = [("（", "）"), ("(", ")"), ("[", "]"), ("【", "】")]
        for (open, close) in pairs where trimmed.first == open {
            guard let closeIndex = trimmed.firstIndex(of: close) else { continue }
            let inner = String(trimmed[trimmed.index(after: trimmed.startIndex)..<closeIndex])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !inner.isEmpty && inner.allSatisfy({ $0.isNumber || "零〇一二三四五六七八九十百千万兩两".contains($0) }) {
                return true
            }
        }
        return false
    }

    private func startsWithListMarker(_ title: String) -> Bool {
        var cursor = title.startIndex
        while cursor < title.endIndex, title[cursor].isNumber {
            cursor = title.index(after: cursor)
        }
        if cursor > title.startIndex, cursor < title.endIndex, "、.．)）".contains(title[cursor]) {
            return true
        }

        guard let first = title.first,
              "零〇一二三四五六七八九十百千万兩两".contains(first),
              title.count > 1 else {
            return false
        }
        let second = title[title.index(after: title.startIndex)]
        return "、.．)）".contains(second)
    }

    private func isDateLikeLine(_ title: String) -> Bool {
        let compact = title.filter { !$0.isWhitespace }
        let separators = compact.filter { ".-/年月日".contains($0) }.count
        let numbers = compact.filter(\.isNumber).count
        return compact.count <= 12 && separators >= 2 && numbers >= 3
    }

    private func parseHeading(_ line: String) -> (title: String, ordinal: Int?, unit: Character, unitIndex: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("第") else { return nil }

        let units = Set("章节篇回卷部集")
        var token = ""
        var titleStart = trimmed.endIndex
        var unit: Character?
        var unitIndex: Int?
        var cursor = trimmed.index(after: trimmed.startIndex)

        while cursor < trimmed.endIndex {
            let character = trimmed[cursor]
            if units.contains(character) {
                unit = character
                unitIndex = trimmed.distance(from: trimmed.startIndex, to: cursor)
                titleStart = trimmed.index(after: cursor)
                break
            }
            token.append(character)
            cursor = trimmed.index(after: cursor)
        }

        guard let unit,
              let unitIndex,
              titleStart < trimmed.endIndex,
              !token.isEmpty,
              token.allSatisfy({ $0.isNumber || "零〇一二三四五六七八九十百千万兩两".contains($0) }) else {
            return nil
        }

        let title = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count > token.count + 1,
              title.count <= 64,
              title.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？!?；;，,")) == nil else {
            return nil
        }
        return (title, chapterOrdinal(from: token), unit, unitIndex)
    }

    private func topLevelHeadings(_ headings: [ChapterHeading]) -> [ChapterHeading] {
        guard let firstUnit = headings.first?.unit,
              headings.allSatisfy({ $0.unit != nil }) else {
            return headings
        }
        let matchingFirstUnit = headings.filter { $0.unit == firstUnit }
        if matchingFirstUnit.count >= 2 {
            return matchingFirstUnit
        }

        let grouped = Dictionary(grouping: headings, by: \.unit)
        let largestGroup = grouped.values.max { $0.count < $1.count } ?? headings
        return largestGroup.count >= 2 ? largestGroup : []
    }

    private func bodyStartHeadingIndex(in headings: [ChapterHeading], text: String) -> Int {
        guard headings.count >= 3 else { return 0 }

        for index in 1..<headings.count {
            guard let previous = headings[index - 1].ordinal,
                  let current = headings[index].ordinal,
                  current <= previous,
                  denseHeadingPrefix(upTo: index, headings: headings, text: text) else {
                continue
            }
            return index
        }
        return 0
    }

    private func denseHeadingPrefix(upTo resetIndex: Int, headings: [ChapterHeading], text: String) -> Bool {
        guard resetIndex >= 2 else { return false }

        for index in 1...resetIndex {
            let previousEnd = headings[index - 1].range.upperBound
            let currentStart = headings[index].range.lowerBound
            let between = text[previousEnd..<currentStart]
            if between.split(separator: "\n").contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                return false
            }
        }
        return true
    }

    private func chapterOrdinal(from token: String) -> Int? {
        if let value = Int(token) {
            return value
        }

        let digits: [Character: Int] = [
            "零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "兩": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]
        if token.allSatisfy({ digits[$0] != nil }) {
            return token.reduce(0) { partial, character in
                partial * 10 + (digits[character] ?? 0)
            }
        }

        if token == "十" { return 10 }
        if token.hasPrefix("十") {
            return 10 + (digits[token.last!] ?? 0)
        }
        if token.hasSuffix("十"), let first = token.first, let tens = digits[first] {
            return tens * 10
        }
        let parts = token.split(separator: "十", maxSplits: 1).map(String.init)
        if parts.count == 2,
           let first = parts[0].first,
           let tens = digits[first],
           let last = parts[1].first,
           let ones = digits[last] {
            return tens * 10 + ones
        }
        return nil
    }

    private func uniqueOutputURL(for heading: String, sourceURL: URL, reservedNames: Set<String>) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let name = outputFileName(for: heading)
        var destination = directory.appendingPathComponent(name)
        var index = 2
        while reservedNames.contains(destination.lastPathComponent) || fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent(FileNameUtilities.numberedCopyName(for: name, index: index))
            index += 1
        }
        return destination.standardizedFileURL
    }

    private func outputFileName(for heading: String) -> String {
        let cleaned = outputTitle(for: heading)
            .components(separatedBy: CharacterSet(charactersIn: "/:"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? "Chapter" : cleaned) + ".txt"
    }

    private func outputTitle(for heading: String) -> String {
        let trimmed = heading.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let parsed = parseHeading(trimmed) else { return trimmed }
        let titleStart = trimmed.index(trimmed.startIndex, offsetBy: parsed.unitIndex + 1)
        let title = trimmed[titleStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? trimmed : title
    }
}

private struct DecodedText {
    let label: String
    let text: String
}

private struct ChapterHeading {
    let title: String
    let ordinal: Int?
    let unit: Character?
    let unitIndex: Int?
    let lineNumber: Int
    let range: Range<String.Index>
}

private struct IndexedLine {
    let trimmed: String
    let lineNumber: Int
    let range: Range<String.Index>
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
