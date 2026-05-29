import Foundation
import Testing
@testable import DualFinderCore

@Suite("BatchRenamePlanner")
struct BatchRenamePlannerTests {
    @Test("generates padded numbered names while preserving extensions")
    func generatesNumberedNames() throws {
        let root = try TemporaryDirectory()
        let items = [
            item(named: "alpha.txt", in: root.url),
            item(named: "beta.md", in: root.url)
        ]

        let previews = try BatchRenamePlanner().previews(
            for: items,
            rule: .numbering(prefix: "Doc-", suffix: "", start: 7, padding: 3, includeOriginalName: false)
        )

        #expect(previews.map(\.newName) == ["Doc-007.txt", "Doc-008.md"])
        #expect(previews.allSatisfy { $0.status == .ready })
    }

    @Test("replaces literal strings case insensitively")
    func replacesLiteralStrings() throws {
        let root = try TemporaryDirectory()
        let items = [item(named: "Report FINAL.txt", in: root.url)]

        let previews = try BatchRenamePlanner().previews(
            for: items,
            rule: .literalReplace(search: "final", replacement: "draft", caseSensitive: false)
        )

        #expect(previews.first?.newName == "Report draft.txt")
    }

    @Test("applies regular expression replacements")
    func appliesRegexReplacement() throws {
        let root = try TemporaryDirectory()
        let items = [item(named: "IMG_1234.jpg", in: root.url)]

        let previews = try BatchRenamePlanner().previews(
            for: items,
            rule: .regularExpression(pattern: #"IMG_(\d+)"#, replacement: "Photo-$1")
        )

        #expect(previews.first?.newName == "Photo-1234.jpg")
    }

    @Test("changes extensions")
    func changesExtensions() throws {
        let root = try TemporaryDirectory()
        let items = [item(named: "notes.text", in: root.url)]

        let previews = try BatchRenamePlanner().previews(
            for: items,
            rule: .changeExtension(".md")
        )

        #expect(previews.first?.newName == "notes.md")
    }

    @Test("renders metadata templates with file-safe dates")
    func rendersMetadataTemplates() throws {
        let root = try TemporaryDirectory()
        let modifiedAt = try #require(Calendar.current.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 29,
            hour: 12,
            minute: 34,
            second: 56
        )))
        let items = [item(named: "clip.mov", in: root.url, modifiedAt: modifiedAt, size: 42)]

        let previews = try BatchRenamePlanner().previews(
            for: items,
            rule: .metadataTemplate("{modifiedDate}_{modifiedTime}_{size}_{base}{extWithDot}")
        )

        #expect(previews.first?.newName == "2026-05-29_12-34-56_42_clip.mov")
    }

    @Test("marks duplicate destinations")
    func marksDuplicateDestinations() throws {
        let root = try TemporaryDirectory()
        let items = [
            item(named: "one.txt", in: root.url),
            item(named: "two.txt", in: root.url)
        ]

        let previews = try BatchRenamePlanner().previews(
            for: items,
            rule: .metadataTemplate("same.txt")
        )

        #expect(previews.allSatisfy { $0.status == .duplicateDestination })
    }

    private func item(
        named name: String,
        in directory: URL,
        modifiedAt: Date? = nil,
        size: Int64? = nil
    ) -> FileItem {
        FileItem(
            url: directory.appendingPathComponent(name),
            name: name,
            kind: .file,
            type: (name as NSString).pathExtension.uppercased(),
            size: size,
            modifiedAt: modifiedAt,
            isHidden: false
        )
    }
}
