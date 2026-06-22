import AppKit
import Foundation
import DualFinderCore

enum FileSizeText {
    static func format(_ size: Int64?) -> String {
        guard let size else { return "--" }
        guard size >= 1_000 else {
            return "\(size) \(size == 1 ? "byte" : "bytes")"
        }

        let units = ["KB", "MB", "GB", "TB", "PB"]
        var value = Double(size)
        var unitIndex = -1
        while value >= 1_000, unitIndex < units.count - 1 {
            value /= 1_000
            unitIndex += 1
        }

        return String(format: "%.3f %@", locale: Locale(identifier: "en_US_POSIX"), value, units[unitIndex])
    }
}

struct SimilarFileReviewState {
    var groups: [SimilarFileNameGroup]
    private(set) var visuallyDeletedURLs: Set<URL>

    init(groups: [SimilarFileNameGroup], visuallyDeletedURLs: Set<URL> = []) {
        self.groups = groups
        self.visuallyDeletedURLs = visuallyDeletedURLs
    }

    var visibleItems: [FileItem] {
        groups.flatMap(\.items)
    }

    mutating func markVisuallyDeleted(_ urls: Set<URL>) {
        visuallyDeletedURLs.formUnion(urls)
    }

    mutating func reconcileDeletedMarkers(with items: [FileItem]) {
        visuallyDeletedURLs.formIntersection(Set(items.map(\.url)))
    }

    func isVisuallyDeleted(_ url: URL) -> Bool {
        visuallyDeletedURLs.contains(url)
    }

    func replacementSelection(afterDeleting deletedURLs: Set<URL>) -> Set<URL> {
        let orderedURLs = visibleItems.map(\.url)
        guard !orderedURLs.isEmpty, !deletedURLs.isEmpty else { return [] }

        let deletedIndexes = deletedURLs.compactMap { orderedURLs.firstIndex(of: $0) }
        guard let firstDeletedIndex = deletedIndexes.min(),
              let lastDeletedIndex = deletedIndexes.max() else {
            return []
        }

        let unavailableURLs = visuallyDeletedURLs.union(deletedURLs)
        let nextStartIndex = min(lastDeletedIndex + 1, orderedURLs.count)
        if nextStartIndex < orderedURLs.count,
           let next = orderedURLs[nextStartIndex...].first(where: { !unavailableURLs.contains($0) }) {
            return [next]
        }

        if firstDeletedIndex > 0,
           let previous = orderedURLs[..<firstDeletedIndex].reversed().first(where: { !unavailableURLs.contains($0) }) {
            return [previous]
        }

        return []
    }
}

struct FileSelectionSnapshot {
    private let exactURLs: Set<URL>
    private let standardizedPaths: Set<String>

    init(selection: Set<URL>) {
        exactURLs = selection
        standardizedPaths = Set(selection.map { $0.standardizedFileURL.path })
    }

    func contains(_ url: URL) -> Bool {
        if exactURLs.contains(url) {
            return true
        }

        if standardizedPaths.contains(url.path) {
            return true
        }

        let standardizedPath = url.standardizedFileURL.path
        return standardizedPath != url.path && standardizedPaths.contains(standardizedPath)
    }
}

enum FileRowSelectionReducer {
    static func selectionAfterMouseDown(
        target: URL,
        currentSelection: Set<URL>,
        orderedURLs: [URL],
        modifierFlags: NSEvent.ModifierFlags
    ) -> Set<URL>? {
        if modifierFlags.contains(.command) {
            return nil
        }

        if modifierFlags.contains(.shift) {
            return rangeSelection(to: target, currentSelection: currentSelection, orderedURLs: orderedURLs)
        }

        return currentSelection.contains(target) ? nil : [target]
    }

    static func selectionAfterMouseUp(
        target: URL,
        currentSelection: Set<URL>,
        orderedURLs: [URL],
        modifierFlags: NSEvent.ModifierFlags
    ) -> Set<URL>? {
        if modifierFlags.contains(.command) {
            var selection = currentSelection
            if selection.contains(target) {
                selection.remove(target)
            } else {
                selection.insert(target)
            }
            return selection
        }

        if modifierFlags.contains(.shift) {
            return nil
        }

        guard currentSelection.contains(target), currentSelection.count > 1 else { return nil }
        return [target]
    }

    private static func rangeSelection(
        to target: URL,
        currentSelection: Set<URL>,
        orderedURLs: [URL]
    ) -> Set<URL> {
        guard let targetIndex = orderedURLs.firstIndex(of: target) else { return [target] }
        let selectedIndexes = currentSelection.compactMap { orderedURLs.firstIndex(of: $0) }
        let anchorIndex = selectedIndexes.min() ?? targetIndex
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        return Set(orderedURLs[bounds])
    }
}

enum FileKeyboardSelectionNavigator {
    static func selectionAfterMove(
        anchorURL: URL?,
        currentSelection: Set<URL>,
        orderedURLs: [URL],
        unavailableURLs: Set<URL> = [],
        delta: Int
    ) -> Set<URL>? {
        guard delta != 0, !orderedURLs.isEmpty else { return nil }

        let anchorIndex = anchorURL.flatMap { orderedURLs.firstIndex(of: $0) }
            ?? orderedURLs.firstIndex { currentSelection.contains($0) }
        let startIndex: Int
        if let anchorIndex {
            startIndex = anchorIndex + (delta > 0 ? 1 : -1)
        } else {
            startIndex = delta > 0 ? 0 : orderedURLs.count - 1
        }

        guard orderedURLs.indices.contains(startIndex) else { return nil }

        let indexes: AnySequence<Int>
        if delta > 0 {
            indexes = AnySequence(startIndex..<orderedURLs.count)
        } else {
            indexes = AnySequence(stride(from: startIndex, through: 0, by: -1))
        }

        guard let nextURL = indexes
            .map({ orderedURLs[$0] })
            .first(where: { !unavailableURLs.contains($0) }) else {
            return nil
        }

        return [nextURL]
    }
}

enum FileListKeyDownFallbackPolicy {
    static func ignoreReasonForSimilarReviewArrowFallback(
        keyCode: UInt16,
        isSimilarFileNavigatorEnabled: Bool,
        isFileListFocused: Bool,
        activePaneSide: PaneSide,
        side: PaneSide,
        relevantModifiers: NSEvent.ModifierFlags,
        isPathFieldFocused: Bool,
        isFileSearchFocused: Bool,
        hasTextResponderFocused: Bool,
        isEmbeddedTerminalFocused: Bool
    ) -> String? {
        guard isSimilarFileNavigatorEnabled, keyCode == 126 || keyCode == 125 else {
            return "not-similar-review-arrow"
        }
        guard !isFileListFocused else { return nil }
        guard activePaneSide == side else { return "inactive-pane" }
        guard relevantModifiers.isEmpty else { return "modifiers" }
        guard !isPathFieldFocused else { return "path-field" }
        guard !isFileSearchFocused else { return "file-search-input" }
        guard !hasTextResponderFocused else { return "text-responder" }
        guard !isEmbeddedTerminalFocused else { return "embedded-terminal" }
        return nil
    }
}
