import Foundation

/// Detects file boundaries in a merged text file (multiple concatenated documents).
///
/// A merged file contains several independent documents, each with its own chapter
/// numbering scheme. This detector identifies boundaries by recognizing:
/// - Chapter-sequence resets (ordinal drops back to 1 after a long run)
/// - Unit-type transitions after a long run (e.g., 节 sequence followed by 章 sequence)
/// - Explicit completion markers between sections (全文完, 全书完, （完）, etc.)
struct TextFileMergedSplitDetector {
    static let dropThreshold = 5
    static let completionMarkers: [String] = ["全文完", "全书完", "全本完"]
    static let completionOnly: [String] = ["完", "（完）", "(完)"]
    static let wrappingPunctuation = CharacterSet(charactersIn: "「」“”‘’《》【】（）()[] \t")

    /// Returns the headings that start each file, or nil if the text does not appear
    /// to be a merged file (fewer than 2 detected boundaries).
    static func detectBoundaries(headings: [ChapterHeading], text: String) -> [ChapterHeading]? {
        let filteredHeadings = removeTableOfContentsHeadings(headings, text: text)
        guard filteredHeadings.count >= 2 else { return nil }

        var boundaries: [ChapterHeading] = [filteredHeadings[0]]
        var maxOrdinalPerUnit: [Character: Int] = [:]
        var rootRank = filteredHeadings[0].hierarchyRank
        if let unit = filteredHeadings[0].unit, let ord = filteredHeadings[0].ordinal {
            maxOrdinalPerUnit[unit] = ord
        }
        var prevUnit = filteredHeadings[0].unit
        var prevEnd = filteredHeadings[0].range.upperBound

        for index in 1..<filteredHeadings.count {
            let heading = filteredHeadings[index]
            let ord = heading.ordinal
            let unit = heading.unit
            let dense = isDenseGap(between: prevEnd, and: heading.range.lowerBound, in: text)
            let hasMarker = hasCompletionMarker(between: prevEnd, and: heading.range.lowerBound, in: text)

            var isBoundary = false
            if hasMarker {
                isBoundary = true
            } else if rootRank == 0,
                      heading.hierarchyRank > rootRank,
                      let previousUnit = prevUnit,
                      (maxOrdinalPerUnit[previousUnit] ?? 0) >= dropThreshold {
                // A long explicitly grouped run followed by an ungrouped
                // chapter heading is a common boundary between source files.
                isBoundary = true
            } else if heading.hierarchyRank <= rootRank, let ord, let unit {
                let sameUnitMax = maxOrdinalPerUnit[unit] ?? 0
                if ord == 1,
                   sameUnitMax - ord >= dropThreshold,
                   sameUnitMax >= dropThreshold {
                    isBoundary = true
                } else if unit != prevUnit,
                          ord == 1,
                          let prevUnit,
                          (maxOrdinalPerUnit[prevUnit] ?? 0) >= dropThreshold,
                          !dense {
                    isBoundary = true
                }
            }

            if isBoundary {
                boundaries.append(heading)
                rootRank = heading.hierarchyRank
                maxOrdinalPerUnit.removeAll()
                if let unit, let ord {
                    maxOrdinalPerUnit[unit] = ord
                }
            } else if let ord, let unit {
                maxOrdinalPerUnit[unit] = max(maxOrdinalPerUnit[unit] ?? 0, ord)
            }
            prevUnit = unit
            prevEnd = heading.range.upperBound
        }

        return boundaries.count >= 2 ? boundaries : nil
    }

    private static func removeTableOfContentsHeadings(
        _ headings: [ChapterHeading],
        text: String
    ) -> [ChapterHeading] {
        guard headings.count >= 6 else { return headings }

        var removed = Set<Int>()
        for start in headings.indices where headings[start].ordinal == 1 {
            guard let unit = headings[start].unit else { continue }
            var cursor = start
            var expected = 2
            while cursor + 1 < headings.count,
                  headings[cursor + 1].unit == unit,
                  headings[cursor + 1].ordinal == expected,
                  isDenseGap(
                    between: headings[cursor].range.upperBound,
                    and: headings[cursor + 1].range.lowerBound,
                    in: text
                  ) {
                cursor += 1
                expected += 1
            }

            guard cursor - start + 1 >= 5,
                  cursor + 1 < headings.count,
                  headings[cursor + 1].unit == unit,
                  headings[cursor + 1].ordinal == 1,
                  isDenseGap(
                    between: headings[cursor].range.upperBound,
                    and: headings[cursor + 1].range.lowerBound,
                    in: text
                  ) else {
                continue
            }
            for index in start...cursor {
                removed.insert(index)
            }
        }

        return headings.enumerated().compactMap { removed.contains($0.offset) ? nil : $0.element }
    }

    private static func isDenseGap(between prevEnd: String.Index, and currStart: String.Index, in text: String) -> Bool {
        let between = text[prevEnd..<currStart]
        return !between.split(separator: "\n").contains(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    private static func hasCompletionMarker(between prevEnd: String.Index, and currStart: String.Index, in text: String) -> Bool {
        let between = text[prevEnd..<currStart]
        for line in between.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            let stripped = trimmed.trimmingCharacters(in: wrappingPunctuation)
            if completionMarkers.contains(stripped) || completionOnly.contains(stripped) {
                return true
            }
        }
        return false
    }
}
