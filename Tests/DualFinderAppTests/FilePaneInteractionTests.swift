import AppKit
import Foundation
import Testing
@testable import DualFinderApp
@testable import DualFinderCore

@Suite("FilePane interactions")
struct FilePaneInteractionTests {
    @MainActor
    @Test("flat view uses selected file parent folder")
    func flatViewUsesSelectedFileParentFolder() throws {
        let root = try AppTestTemporaryDirectory()
        let nested = root.url.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let selectedFile = root.url.appendingPathComponent("Template Manager.html")
        try "html".write(to: selectedFile, atomically: true, encoding: .utf8)
        try "readme".write(to: nested.appendingPathComponent("ReadMe.txt"), atomically: true, encoding: .utf8)

        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let model = DualFinderViewModel(
            initialURL: root.url,
            sortRuleStore: FolderSortRuleStore(defaults: defaults, key: "sort"),
            paneSessionStore: PaneSessionStore(defaults: defaults, key: "session"),
            folderBookmarkStore: FolderBookmarkStore(defaults: defaults, key: "bookmarks"),
            uiLayoutPreferencesStore: UILayoutPreferencesStore(defaults: defaults, key: "layout"),
            logger: AppTestLogger()
        )
        model.refresh(.left)
        model.replaceSelection([selectedFile.standardizedFileURL], on: .left, source: "test")

        model.toggleFlatView(on: .left)

        #expect(model.flatViewRoot(for: .left) == root.url.standardizedFileURL)
        #expect(model.items(for: .left).map(\.url).contains(selectedFile.standardizedFileURL))
        #expect(model.items(for: .left).map(\.url).contains(nested.appendingPathComponent("ReadMe.txt").standardizedFileURL))
        #expect(model.items(for: .left).allSatisfy { !$0.isDirectoryLike })

        model.toggleFlatView(on: .left)

        #expect(model.flatViewRoot(for: .left) == nil)
        #expect(model.pane(for: .left).selectedItemURLs == [selectedFile.standardizedFileURL])
    }

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

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "DualFinder.FilePaneInteractionTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}

private final class AppTestTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DualFinderAppTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

private final class AppTestLogger: AppLogging, @unchecked Sendable {
    func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String]) { }
}
