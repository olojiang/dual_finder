import Foundation
import Testing
@testable import DualFinderCore

@Suite("ConditionalFileSelection")
struct ConditionalFileSelectionTests {
    @Test("selects items with matching extension")
    func selectsMatchingExtension() {
        let root = URL(fileURLWithPath: "/tmp/demo", isDirectory: true)
        let items = [
            FileItem(url: root.appendingPathComponent("a.mp4"), name: "a.mp4", kind: .file, type: "Video", size: 10, modifiedAt: nil, isHidden: false),
            FileItem(url: root.appendingPathComponent("b.txt"), name: "b.txt", kind: .file, type: "Text", size: 10, modifiedAt: nil, isHidden: false)
        ]

        let selected = ConditionalFileSelection.matchingExtension(
            "mp4",
            in: items,
            referenceURL: items[0].url
        )

        #expect(selected.count == 1)
        #expect(selected.contains(items[0].url))
    }

    @Test("selects items modified today")
    func selectsModifiedToday() {
        let root = URL(fileURLWithPath: "/tmp/demo", isDirectory: true)
        let today = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        let items = [
            FileItem(url: root.appendingPathComponent("today.txt"), name: "today.txt", kind: .file, type: "Text", size: 1, modifiedAt: today, isHidden: false),
            FileItem(url: root.appendingPathComponent("old.txt"), name: "old.txt", kind: .file, type: "Text", size: 1, modifiedAt: yesterday, isHidden: false)
        ]

        let selected = ConditionalFileSelection.modifiedToday(in: items)

        #expect(selected.count == 1)
        #expect(selected.contains(items[0].url))
    }

    @Test("selects items larger than threshold")
    func selectsLargerThanThreshold() {
        let root = URL(fileURLWithPath: "/tmp/demo", isDirectory: true)
        let items = [
            FileItem(url: root.appendingPathComponent("small.txt"), name: "small.txt", kind: .file, type: "Text", size: 100, modifiedAt: nil, isHidden: false),
            FileItem(url: root.appendingPathComponent("large.bin"), name: "large.bin", kind: .file, type: "Data", size: 2_000_000, modifiedAt: nil, isHidden: false)
        ]

        let selected = ConditionalFileSelection.largerThan(bytes: 1_000_000, in: items)

        #expect(selected.count == 1)
        #expect(selected.contains(items[1].url))
    }
}
