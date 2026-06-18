import Foundation

public struct SimilarFileNameGroup: Identifiable, Hashable, Sendable {
    public let id: String
    public let items: [FileItem]

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
            guard stem.count >= 4 else { return nil }
            return Candidate(index: index, item: item, stem: stem, fileExtension: fileExtension(for: item.name))
        }
        guard candidates.count >= 2 else { return [] }

        var disjointSet = DisjointSet(count: candidates.count)
        for leftIndex in candidates.indices {
            for rightIndex in candidates.index(after: leftIndex)..<candidates.count {
                if areSimilar(candidates[leftIndex], candidates[rightIndex]) {
                    disjointSet.union(leftIndex, rightIndex)
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
                    nameSortKey(left.item.name).localizedStandardCompare(nameSortKey(right.item.name)) == .orderedAscending
                }
                let groupID = stableGroupID(for: orderedCandidates)
                return SimilarFileNameGroup(
                    id: groupID,
                    items: orderedCandidates.map(\.item)
                )
            }
            .sorted { left, right in
                nameSortKey(left.items[0].name).localizedStandardCompare(nameSortKey(right.items[0].name)) == .orderedAscending
            }
    }

    private static func areSimilar(_ left: Candidate, _ right: Candidate) -> Bool {
        guard left.fileExtension == right.fileExtension else { return false }
        guard left.item.name != right.item.name else { return false }

        let leftStem = left.stem
        let rightStem = right.stem
        if leftStem == rightStem { return true }

        let shorterCount = min(leftStem.count, rightStem.count)
        let longerCount = max(leftStem.count, rightStem.count)
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
        let authorTrimmed = lowercased.components(separatedBy: "作者").first ?? lowercased

        var tokens: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in authorTrimmed.unicodeScalars {
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

        let meaningfulTokens = tokens.filter { token in
            token.count > 1 && !ignoredTokens.contains(token)
        }
        guard !meaningfulTokens.isEmpty else {
            return tokens.joined()
        }

        let longestToken = meaningfulTokens.max { left, right in
            if left.count == right.count {
                return left > right
            }
            return left.count < right.count
        } ?? meaningfulTokens.joined()

        if containsCJK(longestToken), longestToken.count >= 4 {
            return longestToken
        }
        return meaningfulTokens.joined()
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
        "author"
    ]

    private struct Candidate {
        let index: Int
        let item: FileItem
        let stem: String
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
