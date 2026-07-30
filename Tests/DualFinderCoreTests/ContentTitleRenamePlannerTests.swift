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

    @Test("skips watermark line containing URL and extracts next line as title")
    func skipsWatermarkLineWithURLAndExtractsNextLine() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("E009.txt")
        try """
        此文章由情色禁地 http://www.angelfire.com/nj/johnhsu/ 所排板编名,要转请先告知...谢谢!!!!


        女兽医的秘密

        发言人：爱人

        初次写作,请多指教!
        """.write(to: file, atomically: true, encoding: .utf8)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "女兽医的秘密.txt")
        ])
    }

    @Test("extracts title from parenthesized repost marker")
    func extractsTitleFromParenthesizedRepostMarker() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("E007.txt")
        try """
        此文章由情色禁地 http://www.angelfire.com/nj/johnhsu/ 所排板编名,要转请先告知...谢谢!!!!


        （转贴）对话(转寄)


        \tArmanii (阿慢泥)

        wantsex@SexStoryBBS (想要有女人陪)

        标  题: net-sex     ----    SM 篇
        """.write(to: file, atomically: true, encoding: .utf8)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "对话.txt")
        ])
    }

    @Test("preserves content bracket suffixes to avoid duplicate destinations")
    func preservesContentBracketSuffixesToAvoidDuplicateDestinations() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("E014.txt")
        try """
        此文章由情色禁地 http://www.angelfire.com/nj/johnhsu/ 所排板编名,要转请先告知...谢谢!!!!

            大陆买春系列 [桂林篇]  [珠海篇]  [深圳篇]

        From: 小杨
        """.write(to: file, atomically: true, encoding: .utf8)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "大陆买春系列 [桂林篇] [珠海篇] [深圳篇].txt")
        ])
    }

    @Test("skips Chinese watermark prefix without URL")
    func skipsChineseWatermarkPrefixWithoutURL() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("watermark.txt")
        try """
        本文由某某网站收集整理，转载请注明出处
        真正的标题
        正文内容
        """.write(to: file, atomically: true, encoding: .utf8)

        let operations = try ContentTitleRenamePlanner().operations(for: [
            item(named: file.lastPathComponent, in: root.url)
        ])

        #expect(operations == [
            BatchRenameOperation(sourceURL: file, newName: "真正的标题.txt")
        ])
    }

    @Test("appends suffix when destination file already exists on disk")
    func appendsSuffixWhenDestinationFileAlreadyExists() throws {
        let root = try TemporaryDirectory()
        // Pre-create the target filename on disk
        try "existing content".write(
            to: root.url.appendingPathComponent("Title.txt"),
            atomically: true, encoding: .utf8
        )
        let source = root.url.appendingPathComponent("source.txt")
        try "Title\nBody".write(to: source, atomically: true, encoding: .utf8)

        let plan = try ContentTitleRenamePlanner().plan(for: [
            item(named: source.lastPathComponent, in: root.url)
        ])

        #expect(plan.operations == [
            BatchRenameOperation(sourceURL: source, newName: "Title (2).txt")
        ])
        #expect(plan.skipped.isEmpty)
    }

    @Test("appends incrementing suffix when multiple destination files exist")
    func appendsIncrementingSuffixWhenMultipleDestinationsExist() throws {
        let root = try TemporaryDirectory()
        try "a".write(to: root.url.appendingPathComponent("Title.txt"), atomically: true, encoding: .utf8)
        try "b".write(to: root.url.appendingPathComponent("Title (2).txt"), atomically: true, encoding: .utf8)
        let source = root.url.appendingPathComponent("source.txt")
        try "Title\nBody".write(to: source, atomically: true, encoding: .utf8)

        let plan = try ContentTitleRenamePlanner().plan(for: [
            item(named: source.lastPathComponent, in: root.url)
        ])

        #expect(plan.operations == [
            BatchRenameOperation(sourceURL: source, newName: "Title (3).txt")
        ])
    }

    @Test("appends suffix for duplicate destinations within the same batch")
    func appendsSuffixForDuplicateDestinationsWithinBatch() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("one.txt")
        let second = root.url.appendingPathComponent("two.txt")
        let third = root.url.appendingPathComponent("three.txt")
        try "Same Title\nBody".write(to: first, atomically: true, encoding: .utf8)
        try "Same Title\nOther body".write(to: second, atomically: true, encoding: .utf8)
        try "Unique Title\nBody".write(to: third, atomically: true, encoding: .utf8)

        let plan = try ContentTitleRenamePlanner().plan(for: [
            item(named: first.lastPathComponent, in: root.url),
            item(named: second.lastPathComponent, in: root.url),
            item(named: third.lastPathComponent, in: root.url)
        ])

        #expect(plan.operations == [
            BatchRenameOperation(sourceURL: first, newName: "Same Title.txt"),
            BatchRenameOperation(sourceURL: second, newName: "Same Title (2).txt"),
            BatchRenameOperation(sourceURL: third, newName: "Unique Title.txt")
        ])
        #expect(plan.skipped.isEmpty)
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

    @Test("plan aborts when pre-cancelled before processing items")
    func planAbortsWhenPreCancelled() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("a.txt")
        try "Some Title\nbody".write(to: file, atomically: true, encoding: .utf8)

        let cancellation = FileOperationCancellation()
        cancellation.cancel()

        #expect(throws: FileOperationError.cancelled) {
            _ = try ContentTitleRenamePlanner().plan(
                for: [item(named: file.lastPathComponent, in: root.url)],
                cancellation: cancellation
            )
        }
    }

    @Test("plan reports progress after each scanned item")
    func planReportsProgressPerItem() throws {
        let root = try TemporaryDirectory()
        var items: [FileItem] = []
        for index in 0..<3 {
            let name = "doc-\(index).txt"
            let file = root.url.appendingPathComponent(name)
            try "Title \(index)\nbody".write(to: file, atomically: true, encoding: .utf8)
            items.append(item(named: name, in: root.url))
        }

        var reportedCounts: [Int] = []
        let plan = try ContentTitleRenamePlanner().plan(
            for: items,
            progress: { reportedCounts.append($0) }
        )

        #expect(plan.operations.count == 3)
        #expect(reportedCounts == [1, 2, 3])
    }

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
