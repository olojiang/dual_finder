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

        if firstRemovedIndex > orderedURLs.startIndex {
            let previousRange = orderedURLs[..<firstRemovedIndex]
            if let previous = previousRange.reversed().first(where: { !removed.contains($0) }) {
                return previous
            }
        }

        let nextStartIndex = orderedURLs.index(after: lastRemovedIndex)
        guard nextStartIndex < orderedURLs.endIndex else { return nil }
        return orderedURLs[nextStartIndex...].first(where: { !removed.contains($0) })
    }
}
