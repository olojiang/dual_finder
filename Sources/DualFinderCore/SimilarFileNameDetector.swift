import Foundation

public struct SimilarFileNameGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let items: [FileItem]
    public var size: Int64? {
        items.compactMap(\.size).max()
    }

    public init(id: String, items: [FileItem]) {
        self.id = id
        self.items = items
    }
}

public enum SimilarFileNameDetector {
    public static func groups(in items: [FileItem]) -> [SimilarFileNameGroup] {
        let candidates = items.enumerated().compactMap { index, item -> Candidate? in
            guard !item.isDirectoryLike else { return nil }
            let stem = canonicalStem(for: item.name)
            let stemLength = stem.count
            guard stemLength >= 2 else { return nil }
            return Candidate(
                index: index,
                item: item,
                stem: stem,
                stemLength: stemLength,
                fileExtension: fileExtension(for: item.name)
            )
        }
        guard candidates.count >= 2 else { return [] }

        var disjointSet = DisjointSet(count: candidates.count)
        let buckets = Dictionary(grouping: candidates.indices) { index in
            comparisonBucket(for: candidates[index])
        }

        for bucketIndexes in buckets.values where bucketIndexes.count >= 2 {
            for leftOffset in bucketIndexes.indices {
                let leftIndex = bucketIndexes[leftOffset]
                for rightIndex in bucketIndexes[bucketIndexes.index(after: leftOffset)..<bucketIndexes.endIndex] {
                    if areSimilar(candidates[leftIndex], candidates[rightIndex]) {
                        disjointSet.union(leftIndex, rightIndex)
                    }
                }
            }
        }

        let groupedCandidates = Dictionary(grouping: candidates.indices, by: { disjointSet.find($0) })
            .values
            .map { indexes in indexes.map { candidates[$0] } }
            .filter { $0.count >= 2 }

        return groupedCandidates
            .map { groupCandidates in
                let orderedCandidates = groupCandidates.sorted { left, right in
                    compareBySizeThenName(left.item, right.item)
                }
                let groupID = stableGroupID(for: orderedCandidates)
                return SimilarFileNameGroup(
                    id: groupID,
                    items: orderedCandidates.map(\.item)
                )
            }
            .sorted { left, right in
                compareGroupsBySizeThenName(left, right)
            }
    }

    private static func compareGroupsBySizeThenName(_ left: SimilarFileNameGroup, _ right: SimilarFileNameGroup) -> Bool {
        if let result = compareOptionalSizeDescending(left.size, right.size) {
            return result
        }

        let leftName = left.items.first?.name ?? ""
        let rightName = right.items.first?.name ?? ""
        return compareNames(leftName, rightName)
    }

    private static func compareBySizeThenName(_ left: FileItem, _ right: FileItem) -> Bool {
        if let result = compareOptionalSizeDescending(left.size, right.size) {
            return result
        }
        return compareNames(left.name, right.name)
    }

    private static func compareOptionalSizeDescending(_ left: Int64?, _ right: Int64?) -> Bool? {
        switch (left, right) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return nil
        }
    }

    private static func compareNames(_ left: String, _ right: String) -> Bool {
        let keyComparison = nameSortKey(left).localizedStandardCompare(nameSortKey(right))
        if keyComparison != .orderedSame {
            return keyComparison == .orderedAscending
        }

        let nameComparison = left.localizedStandardCompare(right)
        if nameComparison != .orderedSame {
            return nameComparison == .orderedAscending
        }

        return left < right
    }

    private static func comparisonBucket(for candidate: Candidate) -> String {
        "\(candidate.fileExtension)|\(candidate.stem.prefix(2))"
    }

    private static func areSimilar(_ left: Candidate, _ right: Candidate) -> Bool {
        guard left.fileExtension == right.fileExtension else { return false }
        guard left.item.name != right.item.name else { return false }

        let leftStem = left.stem
        let rightStem = right.stem
        if leftStem == rightStem { return true }

        let shorterCount = min(left.stemLength, right.stemLength)
        let longerCount = max(left.stemLength, right.stemLength)
        guard shorterCount >= 4 else { return false }

        if leftStem.hasPrefix(rightStem) || rightStem.hasPrefix(leftStem) {
            return Double(shorterCount) / Double(longerCount) >= 0.5
        }

        let prefixCount = commonPrefixCount(leftStem, rightStem)
        if prefixCount >= max(4, Int(Double(shorterCount) * 0.75)) {
            return true
        }

        return prefixCount >= 2 && diceCoefficient(leftStem, rightStem) >= 0.78
    }

    private static func stableGroupID(for candidates: [Candidate]) -> String {
        let shortestStem = candidates.map(\.stem).min { left, right in
            if left.count == right.count {
                return left < right
            }
            return left.count < right.count
        } ?? ""
        let fileExtension = candidates.first?.fileExtension ?? ""
        return "\(fileExtension)|\(shortestStem)"
    }

    private static func canonicalStem(for name: String) -> String {
        let rawStem = (name as NSString).deletingPathExtension
        let halfWidth = rawStem.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? rawStem
        let stripped = halfWidth.applyingTransform(.stripDiacritics, reverse: false) ?? halfWidth
        let lowercased = stripped.lowercased()
        let metadataTrimmed = trimKnownMetadata(from: lowercased)
        let titleScoped = firstBookTitleContent(in: metadataTrimmed)
        let stemSource = removeBracketedMetadata(from: titleScoped ?? metadataTrimmed)

        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in stemSource.unicodeScalars {
            if CharacterSet.letters.contains(scalar) {
                current.append(scalar)
            } else if !current.isEmpty {
                tokens.append(String(current))
                current.removeAll()
            }
        }
        if !current.isEmpty {
            tokens.append(String(current))
        }

        let meaningfulTokens = tokens.compactMap(normalizedToken)
        guard !meaningfulTokens.isEmpty else {
            return ""
        }

        let minimumCJKTokenLength = titleScoped == nil ? 4 : 2
        let cjkTokens = meaningfulTokens.filter(containsCJK)
        if let longestCJKToken = longestToken(in: cjkTokens),
           longestCJKToken.count >= minimumCJKTokenLength {
            return longestCJKToken
        }
        return meaningfulTokens.joined()
    }

    private static func firstBookTitleContent(in text: String) -> String? {
        if let content = pairedTitleContent(in: text, open: "《", close: "》") {
            return content
        }
        if let content = danglingTitleContent(in: text, close: "》", beforeOpen: "《") {
            return content
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.first == "【",
           let content = pairedTitleContent(in: trimmed, open: "【", close: "】") {
            return content
        }
        if let content = danglingTitleContent(in: text, close: "】", beforeOpen: "【") {
            return content
        }

        return nil
    }

    private static func pairedTitleContent(in text: String, open: Character, close: Character) -> String? {
        guard let openIndex = text.firstIndex(of: open),
              let closeIndex = text[openIndex...].firstIndex(of: close),
              openIndex < closeIndex else {
            return nil
        }

        let contentStart = text.index(after: openIndex)
        let content = String(text[contentStart..<closeIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    private static func danglingTitleContent(in text: String, close: Character, beforeOpen open: Character) -> String? {
        guard let closeIndex = text.firstIndex(of: close),
              closeIndex > text.startIndex else {
            return nil
        }
        if let openIndex = text.firstIndex(of: open),
           openIndex < closeIndex {
            return nil
        }

        let content = String(text[..<closeIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        if let firstScalar = content.unicodeScalars.first,
           CharacterSet.decimalDigits.contains(firstScalar) {
            return nil
        }
        return content
    }

    private static func trimKnownMetadata(from text: String) -> String {
        var endIndex = text.endIndex
        for marker in metadataSeparators {
            guard let range = text.range(of: marker), range.lowerBound < endIndex else {
                continue
            }
            endIndex = range.lowerBound
        }
        return String(text[..<endIndex])
    }

    private static func removeBracketedMetadata(from text: String) -> String {
        var result = ""
        var closingStack: [Character] = []

        for character in text {
            if let close = metadataBracketPairs[character] {
                closingStack.append(close)
                continue
            }
            if closingStack.last == character {
                closingStack.removeLast()
                continue
            }
            if closingStack.isEmpty {
                result.append(character)
            }
        }

        return result
    }

    private static func normalizedToken(_ token: String) -> String? {
        var candidate = token
        var didStrip = true
        while didStrip {
            didStrip = false
            for prefix in ignoredPrefixes where candidate.hasPrefix(prefix) {
                candidate.removeFirst(prefix.count)
                didStrip = true
                break
            }
            if didStrip {
                continue
            }
            for suffix in ignoredSuffixes where candidate.hasSuffix(suffix) {
                candidate.removeLast(suffix.count)
                didStrip = true
                break
            }
        }

        guard candidate.count > 1, !ignoredTokens.contains(candidate) else {
            return nil
        }
        return candidate
    }

    private static func longestToken(in tokens: [String]) -> String? {
        tokens.max { left, right in
            if left.count == right.count {
                return left.localizedStandardCompare(right) == .orderedDescending
            }
            return left.count < right.count
        }
    }

    private static func fileExtension(for name: String) -> String {
        (name as NSString).pathExtension.lowercased()
    }

    private static func nameSortKey(_ name: String) -> String {
        let latin = name.applyingTransform(.toLatin, reverse: false) ?? name
        let stripped = latin.applyingTransform(.stripDiacritics, reverse: false) ?? latin
        return stripped.lowercased()
    }

    private static func commonPrefixCount(_ left: String, _ right: String) -> Int {
        var count = 0
        for (leftCharacter, rightCharacter) in zip(left, right) {
            guard leftCharacter == rightCharacter else { break }
            count += 1
        }
        return count
    }

    private static func diceCoefficient(_ left: String, _ right: String) -> Double {
        let leftBigrams = bigramCounts(left)
        let rightBigrams = bigramCounts(right)
        guard !leftBigrams.isEmpty, !rightBigrams.isEmpty else { return 0 }

        let overlap = leftBigrams.reduce(0) { total, entry in
            total + min(entry.value, rightBigrams[entry.key] ?? 0)
        }
        return Double(2 * overlap) / Double(leftBigrams.values.reduce(0, +) + rightBigrams.values.reduce(0, +))
    }

    private static func bigramCounts(_ text: String) -> [String: Int] {
        let characters = Array(text)
        guard characters.count >= 2 else { return [:] }

        var counts: [String: Int] = [:]
        for index in 0..<(characters.count - 1) {
            let bigram = String(characters[index...index + 1])
            counts[bigram, default: 0] += 1
        }
        return counts
    }

    private static func containsCJK(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
    }

    private static let ignoredTokens: Set<String> = [
        "copy",
        "副本",
        "最终",
        "final",
        "author",
        "未知",
        "佚名",
        "不详",
        "已完结",
        "未完结",
        "完结",
        "未完",
        "完",
        "章",
        "卷",
        "部",
        "番外",
        "正文",
        "全文",
        "校对"
    ]

    private static let ignoredPrefixes: [String] = [
        "经典之"
    ]

    private static let ignoredSuffixes: [String] = [
        "校对版全本",
        "无删全本",
        "未删全本",
        "完整版",
        "完结版",
        "校对版",
        "无删版",
        "未删版",
        "修改版",
        "修订版",
        "精校版",
        "加强版",
        "增强版",
        "改版",
        "原版",
        "加料版",
        "加料",
        "已完结",
        "未完结",
        "完结",
        "未完",
        "全本",
        "完本"
    ]

    private static let metadataSeparators: [String] = [
        "作者",
        " - ",
        " by "
    ]

    private static let metadataBracketPairs: [Character: Character] = [
        "(": ")",
        "（": "）",
        "[": "]",
        "［": "］",
        "{": "}",
        "【": "】"
    ]

    private struct Candidate {
        let index: Int
        let item: FileItem
        let stem: String
        let stemLength: Int
        let fileExtension: String
    }
}

private struct DisjointSet {
    private var parents: [Int]

    init(count: Int) {
        parents = Array(0..<count)
    }

    mutating func find(_ index: Int) -> Int {
        if parents[index] != index {
            parents[index] = find(parents[index])
        }
        return parents[index]
    }

    mutating func union(_ left: Int, _ right: Int) {
        let leftRoot = find(left)
        let rightRoot = find(right)
        guard leftRoot != rightRoot else { return }
        parents[rightRoot] = leftRoot
    }
}
