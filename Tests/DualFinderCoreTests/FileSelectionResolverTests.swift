import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileSelectionResolver")
struct FileSelectionResolverTests {
    @Test("prefers previous item after removing selected file")
    func prefersPreviousItem() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[1]], from: urls)

        #expect(replacement == urls[0])
    }

    @Test("falls back to next item when removed file has no previous item")
    func fallsBackToNextItem() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[0]], from: urls)

        #expect(replacement == urls[1])
    }

    @Test("returns nil when no adjacent item remains")
    func returnsNilWhenNoAdjacentItemRemains() {
        let urls = fileURLs(["a.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[0]], from: urls)

        #expect(replacement == nil)
    }

    @Test("uses previous before removed range for multi-selection")
    func usesPreviousBeforeRemovedRange() {
        let urls = fileURLs(["a.txt", "b.txt", "c.txt", "d.txt"])

        let replacement = FileSelectionResolver.replacementAfterRemoving([urls[1], urls[2]], from: urls)

        #expect(replacement == urls[0])
    }

    private func fileURLs(_ names: [String]) -> [URL] {
        names.map { URL(fileURLWithPath: "/tmp/\($0)") }
    }
}
