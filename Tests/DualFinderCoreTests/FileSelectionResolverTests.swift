import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileSelectionResolver")
struct FileSelectionResolverTests {
    @Test("prefers next item after removing selected file")
    func prefersNextItem() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[1]], from: urls)

        #expect(replacement == urls[2])
    }

    @Test("falls back to previous item when removed file has no next item")
    func fallsBackToPreviousItem() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[2]], from: urls)

        #expect(replacement == urls[1])
    }

    @Test("returns nil when no adjacent item remains")
    func returnsNilWhenNoAdjacentItemRemains() {
        let urls = fileURLs(["a.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[0]], from: urls)

        #expect(replacement == nil)
    }

    @Test("prefers next item after a removed range")
    func prefersNextAfterRemovedRange() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt", "d.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[1], urls[2]], from: urls)

        #expect(replacement == urls[3])
    }

    private func fileURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0)") }
    }
}
