import CoreFoundation
import Foundation
import Testing
@testable import DualFinderCore

@Suite("ContentTitleRenamePlanner")
struct ContentTitleRenamePlannerTests {
    @Test("uses the first content title as a txt filename")
    func usesFirstContentTitleAsTxtFilename() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("New Text Document (4).txt")
        try """
        [2008-08-02] [Repost][Category] Found Title
        Body text
        """.write(to: file, atomically: true, encoding: .utf8)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "Found Title.txt")
        ])
    }

    @Test("decodes GBK titles before generating names")
    func decodesGBKTitlesBeforeGeneratingNames() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("wrong.txt")
        let sourceText = "[2008-08-02] [转帖][分类] 养母的诱惑\n正文"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "养母的诱惑.txt")
        ])
    }

    @Test("rejects files without a title candidate")
    func rejectsFilesWithoutTitleCandidate() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("blank.txt")
        try "\n\n---\n".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: ContentTitleRenameError.self) {
            try ContentTitleRenamePlanner().operations(for: [
                item(named: file.lastPathComponent, in: root.url)
            ])
        }
    }

    @Test("skips table of contents and message headers before choosing a title")
    func skipsNonTitlePrefaceLines() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("wrong.txt")
        try """
        目录
        CHAPTER 1
        发信人: somebody@example.com
        合适的标题
        正文
        """.write(to: file, atomically: true, encoding: .utf8)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "合适的标题.txt")
        ])
    }

    @Test("plan skips duplicate destinations instead of failing the whole batch")
    func planSkipsDuplicateDestinations() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("one.txt")
        let second = root.url.appendingPathComponent("two.txt")
        let third = root.url.appendingPathComponent("three.txt")
        try "Same Title\nBody".write(to: first, atomically: true, encoding: .utf8)
        try "Same Title\nOther body".write(to: second, atomically: true, encoding: .utf8)
        try "Unique Title\nBody".write(to: third, atomically: true, encoding: .utf8)

        let plan = ContentTitleRenamePlanner().plan(for: [
            item(named: first.lastPathComponent, in: root.url),
            item(named: second.lastPathComponent, in: root.url),
            item(named: third.lastPathComponent, in: root.url)
        ])

        #expect(plan.operations == [
            BatchRenameOperation(sourceURL: first, newName: "Same Title.txt"),
            BatchRenameOperation(sourceURL: third, newName: "Unique Title.txt")
        ])
        #expect(plan.skipped == [
            ContentTitleRenameSkippedItem(
                sourceURL: second,
                reason: .duplicateDestination(root.url.appendingPathComponent("Same Title.txt").standardizedFileURL)
            )
        ])
    }

    private func item(named name: String, in directory: URL) -> FileItem {
        FileItem(
            url: directory.appendingPathComponent(name),
            name: name,
            kind: .file,
            type: (name as NSString).pathExtension.uppercased(),
            size: nil,
            modifiedAt: nil,
            isHidden: false
        )
    }

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
