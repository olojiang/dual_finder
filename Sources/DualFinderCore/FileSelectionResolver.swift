import Foundation

public enum FileSelectionResolver {
    public static func replacementAfterRemoving(_ removedURLs: [URL], from orderedURLs: [URL]) -> URL? {
        guard !removedURLs.isEmpty, !orderedURLs.isEmpty else { return nil }

        let removed = Set(removedURLs)
        let removedIndexes = removedURLs.compactMap { orderedURLs.firstIndex(of: $0) }
        guard let firstRemovedIndex = removedIndexes.min(),
              let lastRemovedIndex = removedIndexes.max()
        else {
            return nil
        }

        let nextStartIndex = orderedURLs.index(after: lastRemovedIndex)
        if nextStartIndex < orderedURLs.endIndex,
           let next = orderedURLs[nextStartIndex...].first(where: { !removed.contains($0) }) {
            return next
        }

        if firstRemovedIndex > orderedURLs.startIndex {
            let previousRange = orderedURLs[..<firstRemovedIndex]
            return previousRange.reversed().first(where: { !removed.contains($0) })
        }

        return nil
    }
}
