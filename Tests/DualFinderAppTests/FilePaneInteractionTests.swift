import AppKit
import Foundation
import Testing
@testable import DualFinderApp
@testable import DualFinderCore

@Suite("FilePane interactions")
struct FilePaneInteractionTests {
    @Test("formats file sizes with three fractional digits")
    func formatsFileSizesWithThreeFractionalDigits() {
        #expect(FileSizeText.format(1_234_567) == "1.235 MB")
        #expect(FileSizeText.format(699_000) == "699.000 KB")
        #expect(FileSizeText.format(nil) == "--")
    }

    @Test("keeps visually deleted similar files in the review snapshot")
    func keepsVisuallyDeletedSimilarFilesInReviewSnapshot() {
        let first = file("一千零一夜 2003.txt")
        let second = file("一千零一夜 2008.txt")
        let third = file("一千零一夜 2010.txt")
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|一千零一夜", items: [first, second, third])
        ])

        state.markVisuallyDeleted([second.url])

        #expect(state.visibleItems.map(\.url) == [first.url, second.url, third.url])
        #expect(state.isVisuallyDeleted(second.url))
        #expect(!state.isVisuallyDeleted(first.url))
    }

    @Test("moves focus to next undeleted similar file after deletion")
    func movesFocusToNextUndeletedSimilarFileAfterDeletion() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|a", items: urls.map(file))
        ])

        state.markVisuallyDeleted([urls[1]])

        #expect(state.replacementSelection(afterDeleting: [urls[1]]) == [urls[2]])
    }

    @Test("moves focus to previous undeleted similar file when deleted item has no next item")
    func movesFocusToPreviousUndeletedSimilarFileWhenNoNextItemExists() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|a", items: urls.map(file))
        ])

        state.markVisuallyDeleted([urls[2]])

        #expect(state.replacementSelection(afterDeleting: [urls[2]]) == [urls[1]])
    }

    @Test("skips visually deleted rows when moving focus after deletion")
    func skipsVisuallyDeletedRowsWhenMovingFocusAfterDeletion() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        var state = SimilarFileReviewState(groups: [
            SimilarFileNameGroup(id: "txt|a", items: urls.map(file))
        ])

        state.markVisuallyDeleted([urls[1], urls[2]])

        #expect(state.replacementSelection(afterDeleting: [urls[1]]) == [urls[0]])
    }

    @Test("command click toggles selection on mouse up without disturbing mouse down selection")
    func commandClickTogglesSelectionOnMouseUp() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])
        let selected: Set<URL> = [urls[0]]

        let mouseDownSelection = FileRowSelectionReducer.selectionAfterMouseDown(
            target: urls[1],
            currentSelection: selected,
            orderedURLs: urls,
            modifierFlags: [.command]
        )
        let mouseUpSelection = FileRowSelectionReducer.selectionAfterMouseUp(
            target: urls[1],
            currentSelection: selected,
            orderedURLs: urls,
            modifierFlags: [.command]
        )

        #expect(mouseDownSelection == nil)
        #expect(mouseUpSelection == [urls[0], urls[1]])
    }

    private func file(_ name: String) -> FileItem {
        file(URL(fileURLWithPath: "/tmp/\(name)"))
    }

    private func file(_ url: URL) -> FileItem {
        FileItem(
            url: url,
            name: url.lastPathComponent,
            kind: .file,
            type: "text",
            size: 1,
            modifiedAt: nil,
            isHidden: false
        )
    }

    private func fileURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0)") }
    }
}
