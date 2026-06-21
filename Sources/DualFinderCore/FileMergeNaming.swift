import Foundation

public enum FileMergeNaming {
    public static let fallbackBaseName = "Merged Files"

    public static func suggestedName(for urls: [URL]) -> String {
        suggestedName(forNames: urls.map(\.lastPathComponent))
    }

    public static func suggestedName(forNames names: [String]) -> String {
        let normalizedNames = names.filter { !FileNameUtilities.isBlank($0) }
        guard normalizedNames.count >= 2 else {
            return fallbackName(for: normalizedNames)
        }

        let prefixSuffixCandidate = sanitizedName(commonPrefixSuffixName(normalizedNames))
        let segmentCandidate = sanitizedName(commonSegmentName(normalizedNames))
        let substringCandidate = sanitizedName(commonBaseSubstringName(normalizedNames))
        let sequenceCandidate = sanitizedName(commonSubsequence(normalizedNames))

        let candidates = [segmentCandidate, prefixSuffixCandidate, substringCandidate]
            .filter(isUsefulCandidate)
            .sorted { meaningfulLength($0) > meaningfulLength($1) }
        if let candidate = candidates.first {
            return candidate
        }

        if isUsefulCandidate(sequenceCandidate) {
            return sequenceCandidate
        }

        return fallbackName(for: normalizedNames)
    }

    private static func fallbackName(for names: [String]) -> String {
        let extensions = Set(names.map { FileNameUtilities.extensionName(for: $0) })
        if extensions.count == 1, let ext = extensions.first, !ext.isEmpty {
            return "\(fallbackBaseName).\(ext)"
        }
        return fallbackBaseName
    }

    private static func commonPrefix(_ values: [String]) -> String {
        guard var prefix = values.first else { return "" }
        for value in values.dropFirst() {
            while !prefix.isEmpty && !value.hasPrefix(prefix) {
                prefix.removeLast()
            }
        }
        return prefix
    }

    private static func commonSuffix(_ values: [String]) -> String {
        let reversed = values.map { String($0.reversed()) }
        return String(commonPrefix(reversed).reversed())
    }

    private static func commonPrefixSuffixName(_ values: [String]) -> String {
        let prefix = commonPrefix(values)
        let suffixCandidates = values.map { String($0.dropFirst(prefix.count)) }
        let suffix = commonSuffix(suffixCandidates)
        return prefix + suffix
    }

    private static func commonSegmentName(_ values: [String]) -> String {
        let baseNames = values.map(FileNameUtilities.baseName(for:))
        let prefix = commonPrefix(baseNames)
        let suffixCandidates = baseNames.map { String($0.dropFirst(prefix.count)) }
        let suffix = commonSuffix(suffixCandidates)
        let middles = suffixCandidates.map { value in
            suffix.isEmpty ? value : String(value.dropLast(suffix.count))
        }
        let middleSubstring = cleanedSharedSubstring(longestCommonSubstring(middles))
        let base = prefix + middleSubstring + suffix
        let extensions = Set(values.map { FileNameUtilities.extensionName(for: $0) })
        if extensions.count == 1, let ext = extensions.first, !ext.isEmpty, !base.isEmpty {
            return "\(base).\(ext)"
        }
        return base
    }

    private static func commonSubsequence(_ values: [String]) -> String {
        guard let first = values.first else { return "" }
        var sequence = first.map { String($0) }
        for value in values.dropFirst() {
            sequence = longestCommonSubsequence(sequence, value.map { String($0) })
            guard !sequence.isEmpty else { return "" }
        }
        return sequence.joined()
    }

    private static func longestCommonSubsequence(_ left: [String], _ right: [String]) -> [String] {
        guard !left.isEmpty, !right.isEmpty else { return [] }
        var lengths = Array(
            repeating: Array(repeating: 0, count: right.count + 1),
            count: left.count + 1
        )

        for leftIndex in 1...left.count {
            for rightIndex in 1...right.count {
                if left[leftIndex - 1] == right[rightIndex - 1] {
                    lengths[leftIndex][rightIndex] = lengths[leftIndex - 1][rightIndex - 1] + 1
                } else {
                    lengths[leftIndex][rightIndex] = max(
                        lengths[leftIndex - 1][rightIndex],
                        lengths[leftIndex][rightIndex - 1]
                    )
                }
            }
        }

        var result: [String] = []
        var leftIndex = left.count
        var rightIndex = right.count
        while leftIndex > 0, rightIndex > 0 {
            if left[leftIndex - 1] == right[rightIndex - 1] {
                result.append(left[leftIndex - 1])
                leftIndex -= 1
                rightIndex -= 1
            } else if lengths[leftIndex - 1][rightIndex] >= lengths[leftIndex][rightIndex - 1] {
                leftIndex -= 1
            } else {
                rightIndex -= 1
            }
        }

        return result.reversed()
    }

    private static func commonBaseSubstringName(_ values: [String]) -> String {
        let baseNames = values.map(FileNameUtilities.baseName(for:))
        let substring = cleanedSharedSubstring(longestCommonSubstring(baseNames))
        let extensions = Set(values.map { FileNameUtilities.extensionName(for: $0) })
        if extensions.count == 1, let ext = extensions.first, !ext.isEmpty, !substring.isEmpty {
            return "\(substring).\(ext)"
        }
        return substring
    }

    private static func longestCommonSubstring(_ values: [String]) -> String {
        guard let shortest = values.min(by: { $0.count < $1.count }) else { return "" }
        let characters = shortest.map { String($0) }
        guard !characters.isEmpty else { return "" }

        var best = ""
        for start in characters.indices {
            for end in stride(from: characters.count, through: start + 1, by: -1) {
                let candidate = characters[start..<end].joined()
                guard candidate.count > best.count else { break }
                if values.allSatisfy({ $0.contains(candidate) }) {
                    best = candidate
                    break
                }
            }
        }
        return best
    }

    private static func sanitizedName(_ name: String) -> String {
        let sanitized = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = FileNameUtilities.baseName(for: sanitized)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_\n\t"))
        let ext = FileNameUtilities.extensionName(for: sanitized)
        guard !base.isEmpty, !ext.isEmpty else {
            return sanitized
        }
        return "\(base).\(ext)"
    }

    private static func cleanedSharedSubstring(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: sharedSubstringBoundaryCharacters)
        cleaned = droppingLeadingNoiseToken(from: cleaned)
        cleaned = droppingTrailingNoiseToken(from: cleaned)
        return cleaned.trimmingCharacters(in: sharedSubstringBoundaryCharacters)
    }

    private static var sharedSubstringBoundaryCharacters: CharacterSet {
        CharacterSet(charactersIn: " .-_–—|·・/\\:：,，;；")
    }

    private static func droppingLeadingNoiseToken(from value: String) -> String {
        guard let separatorRange = value.rangeOfCharacter(from: sharedSubstringBoundaryCharacters) else {
            return value
        }
        let token = String(value[..<separatorRange.lowerBound])
        guard isNoiseToken(token) else {
            return value
        }
        return String(value[separatorRange.upperBound...])
    }

    private static func droppingTrailingNoiseToken(from value: String) -> String {
        guard let separatorRange = value.rangeOfCharacter(
            from: sharedSubstringBoundaryCharacters,
            options: .backwards
        ) else {
            return value
        }
        let token = String(value[separatorRange.upperBound...])
        guard isNoiseToken(token) else {
            return value
        }
        return String(value[..<separatorRange.lowerBound])
    }

    private static func isNoiseToken(_ value: String) -> Bool {
        if value.count == 1, value.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }) {
            return true
        }
        return !value.isEmpty && value.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
    }

    private static func isUsefulCandidate(_ name: String) -> Bool {
        guard !FileNameUtilities.isBlank(name), !name.hasPrefix(".") else { return false }
        return meaningfulLength(name) >= 2
    }

    private static func meaningfulLength(_ name: String) -> Int {
        FileNameUtilities.baseName(for: name)
            .trimmingCharacters(in: CharacterSet(charactersIn: " .-_\n\t"))
            .count
    }
}
