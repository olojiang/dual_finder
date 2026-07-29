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
        let mergedHeadings = mergedDetectionHeadings(in: text, chapterHeadings: headings)

        if let mergedBoundaries = TextFileMergedSplitDetector.detectBoundaries(headings: mergedHeadings, text: text),
           mergedBoundaries.count >= 2 {
            let adjustedBoundaries = rebalanceMergedBoundaries(
                mergedBoundaries,
                candidates: mergedHeadings,
                text: text,
                sourceURL: sourceURL
            )
            let chapters = buildChapters(from: adjustedBoundaries, text: text, sourceURL: sourceURL)
            if chapters.count >= 2 {
                return TextFileSplitPreview(
                    sourceURL: sourceURL.standardizedFileURL,
                    detectedEncoding: decoded.label,
                    chapters: chapters
                )
            }
        }

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

    private func buildChapters(
        from boundaries: [ChapterHeading],
        text: String,
        sourceURL: URL
    ) -> [TextFileSplitChapterPreview] {
        var reservedOutputNames = Set<String>()
        return boundaries.enumerated().map { index, heading in
            let end = index + 1 < boundaries.count ? boundaries[index + 1].range.lowerBound : text.endIndex
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
                    hierarchyRank: parsed.hierarchyRank,
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

    private func mergedDetectionHeadings(in text: String, chapterHeadings: [ChapterHeading]) -> [ChapterHeading] {
        var candidates = chapterHeadings
        let completionMarkerPositions = completionMarkerPositions(in: text)
        if let first = chapterHeadings.first,
           first.range.lowerBound > text.startIndex,
           text.distance(from: text.startIndex, to: first.range.lowerBound) >= 128,
           !completionMarkerPositions.isEmpty {
            candidates.insert(
                ChapterHeading(
                    title: "Merged prefix",
                    ordinal: nil,
                    unit: nil,
                    unitIndex: nil,
                    hierarchyRank: 1,
                    lineNumber: 1,
                    range: text.startIndex..<text.startIndex
                ),
                at: 0
            )
        }

        let articleHeadings = standaloneArticleHeadings(in: text).filter { article in
            guard !chapterHeadings.contains(where: { chapter in chapter.range == article.range }) else {
                return false
            }
            guard isLikelyMergedDocumentTitle(article.title) else { return false }
            let previousEnd = chapterHeadings.last(where: { $0.range.upperBound <= article.range.lowerBound })?.range.upperBound
                ?? text.startIndex
            return completionMarkerPositions.contains { $0 >= previousEnd && $0 < article.range.lowerBound }
        }
        return (candidates + articleHeadings)
            .sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func completionMarkerPositions(in text: String) -> [String.Index] {
        let markers = ["全文完", "全书完", "全本完", "（完）", "(完)"]
        var positions: [String.Index] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n") ?? text.endIndex
            let line = text[lineStart..<lineEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            if markers.contains(where: { line.contains($0) }) {
                positions.append(lineStart)
            }
            guard lineEnd < text.endIndex else { break }
            lineStart = text.index(after: lineEnd)
        }
        return positions
    }

    private func isLikelyMergedDocumentTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.hasPrefix("第"),
              !trimmed.hasPrefix("（"),
              !trimmed.hasPrefix("("),
              !trimmed.first!.isNumber,
              !trimmed.contains("【"),
              !trimmed.contains("目录"),
              !trimmed.contains("待续"),
              !trimmed.contains("文心阁"),
              !trimmed.contains("＊"),
              !trimmed.contains("*") else {
            return false
        }
        guard trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "=─—<>±")) == nil else {
            return false
        }
        return trimmed.unicodeScalars.contains {
            (0x4E00...0x9FFF).contains(Int($0.value)) || (0x41...0x5A).contains(Int($0.value))
        }
    }

    private func rebalanceMergedBoundaries(
        _ boundaries: [ChapterHeading],
        candidates: [ChapterHeading],
        text: String,
        sourceURL: URL
    ) -> [ChapterHeading] {
        guard let expectedCount = expectedMergedFileCount(from: sourceURL),
              expectedCount >= 2,
              boundaries.count != expectedCount else {
            return boundaries
        }

        let completionPositions = completionMarkerPositions(in: text)
        if boundaries.count > expectedCount {
            let rankedIndices = boundaries.indices.dropFirst().sorted { lhs, rhs in
                let leftScore = boundaryCandidateScore(boundaries[lhs], completionPositions: completionPositions)
                let rightScore = boundaryCandidateScore(boundaries[rhs], completionPositions: completionPositions)
                return leftScore == rightScore ? lhs < rhs : leftScore > rightScore
            }
            let selectedIndices = Set([boundaries.startIndex] + Array(rankedIndices.prefix(expectedCount - 1)))
            return boundaries.enumerated()
                .compactMap { selectedIndices.contains($0.offset) ? $0.element : nil }
        }

        var selected = boundaries
        let selectedLineNumbers = Set(selected.map(\.lineNumber))
        let additions = candidates
            .filter { !selectedLineNumbers.contains($0.lineNumber) }
            .filter { candidate in
                guard candidate.ordinal != nil || candidate.unit == nil else { return false }
                let title = candidate.title
                return !title.contains("目录")
                    && !title.contains("作者")
                    && !title.contains("待续")
                    && !title.contains("新书")
                    && !title.contains("字数")
                    && !title.contains("人物志")
                    && !title.contains("全文完")
                    && !title.contains("±")
                    && !(candidate.hierarchyRank == 0 && candidate.ordinal != 1)
            }
            .sorted { lhs, rhs in
                boundaryCandidateScore(lhs, completionPositions: completionPositions)
                    > boundaryCandidateScore(rhs, completionPositions: completionPositions)
            }

        for candidate in additions where selected.count < expectedCount {
            selected.append(candidate)
        }
        return selected.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

    private func expectedMergedFileCount(from sourceURL: URL) -> Int? {
        let name = sourceURL.deletingPathExtension().lastPathComponent
        let chineseNumerics = "零〇一二三四五六七八九十百千万两兩"
        if let match = name.range(
            of: #"[零〇一二三四五六七八九十百千万两兩]+(?:篇|部)(?:小说|作品|合集)?"#,
            options: .regularExpression
        ) {
            let matched = String(name[match])
            let token = String(matched.prefix { chineseNumerics.contains($0) })
            if let count = chapterOrdinal(from: token), count >= 2 {
                return count
            }
        }

        let patterns = [
            #"\d+个合并文件"#,
            #"共\d+(?:篇|部|本|个)"#,
            #"(?:\[\d+篇\]|（\d+篇）|\(\d+篇\))"#
        ]
        for pattern in patterns {
            guard let match = name.range(of: pattern, options: .regularExpression) else {
                continue
            }
            let digits = name[match].filter(\.isNumber)
            if let count = Int(digits), count >= 2 {
                return count
            }
        }
        return nil
    }

    private func boundaryCandidateScore(
        _ heading: ChapterHeading,
        completionPositions: [String.Index]
    ) -> Int {
        var score = 0
        if heading.ordinal == 1 { score += 80 }
        if heading.hierarchyRank == 0 { score += 20 }
        if heading.unit == "节" { score -= 100 }
        if heading.unit == nil { score += 15 }
        if completionPositions.contains(where: { $0 < heading.range.lowerBound }) { score += 10 }
        return score
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
                hierarchyRank: 1,
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
              !title.contains("人物志"),
              !title.hasPrefix("作者"),
              !startsWithParenthesizedSectionMarker(title),
              !startsWithListMarker(title),
              !isDateLikeLine(title) else {
            return false
        }

        let prosePunctuation = CharacterSet(charactersIn: "。！？!?；;，,：:“”「」『』")
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

    private func parseHeading(_ line: String) -> (title: String, ordinal: Int?, unit: Character, unitIndex: Int, hierarchyRank: Int)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        let units = Set("章节篇回卷部集")
        let chineseNumerics = "零〇一二三四五六七八九十百千万兩两"

        struct HeadingMatch {
            let token: String
            let unit: Character
            let markerIndex: Int
            let unitIndex: Int
            let hasTextAfter: Bool
        }

        var matches: [HeadingMatch] = []
        var token = ""
        var markerIndex = 0
        var cursor = trimmed.startIndex

        while cursor < trimmed.endIndex {
            let character = trimmed[cursor]
            if character == "第" {
                token = ""
                markerIndex = trimmed.distance(from: trimmed.startIndex, to: cursor)
            } else if units.contains(character) {
                let unitIndex = trimmed.distance(from: trimmed.startIndex, to: cursor)
                let titleStart = trimmed.index(after: cursor)
                let hasTextAfter = titleStart < trimmed.endIndex
                    && !trimmed[titleStart...].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !token.isEmpty,
                   token.allSatisfy({ $0.isNumber || chineseNumerics.contains($0) }) {
                    matches.append(HeadingMatch(token: token, unit: character, markerIndex: markerIndex, unitIndex: unitIndex, hasTextAfter: hasTextAfter))
                }
                token = ""
            } else {
                token.append(character)
            }
            cursor = trimmed.index(after: cursor)
        }

        guard let firstMatch = matches.first, firstMatch.markerIndex <= 24 else {
            return nil
        }

        let chosen: HeadingMatch
        if let lastWithText = matches.last(where: { $0.hasTextAfter }) {
            chosen = lastWithText
        } else {
            chosen = matches[0]
        }

        let title = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = String(trimmed[..<trimmed.index(trimmed.startIndex, offsetBy: firstMatch.markerIndex)])
        let titleSuffix = String(trimmed[trimmed.index(trimmed.startIndex, offsetBy: chosen.unitIndex + 1)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard title.count > chosen.token.count + 1,
              title.count <= 64,
              !prefix.contains("新书"),
              !prefix.contains("推荐"),
              !prefix.contains("介绍"),
              !prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("（"),
              !prefix.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("("),
              !(titleSuffix.hasPrefix("《") && (chapterOrdinal(from: chosen.token) ?? 0) > 1),
              !title.contains("字数:"),
              title.rangeOfCharacter(from: CharacterSet(charactersIn: "。！？!?；;，,")) == nil else {
            return nil
        }
        let chosenIndex = matches.lastIndex { match in
            match.token == chosen.token
                && match.unit == chosen.unit
                && match.unitIndex == chosen.unitIndex
        } ?? 0
        let hierarchyRank: Int
        if matches[..<chosenIndex].contains(where: { $0.unit == "部" || $0.unit == "卷" }) {
            hierarchyRank = 0
        } else if chosen.unit == "节" {
            hierarchyRank = 2
        } else {
            hierarchyRank = 1
        }
        return (title, chapterOrdinal(from: chosen.token), chosen.unit, chosen.unitIndex, hierarchyRank)
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

struct ChapterHeading {
    let title: String
    let ordinal: Int?
    let unit: Character?
    let unitIndex: Int?
    let hierarchyRank: Int
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
