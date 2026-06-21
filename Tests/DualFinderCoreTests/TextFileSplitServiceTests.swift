import Foundation
import Testing
@testable import DualFinderCore

@Suite("TextFileSplitService")
struct TextFileSplitServiceTests {
    @Test("skips a leading table of contents before splitting body chapters")
    func skipsLeadingTableOfContents() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        2013

        第01篇 第一篇
        第02篇 第二篇
        第03篇 第三篇


        第01篇 第一篇
        正文一
        第02篇 第二篇
        正文二
        第03篇 第三篇
        正文三
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.map(\.heading) == [
            "第01篇 第一篇",
            "第02篇 第二篇",
            "第03篇 第三篇"
        ])
        #expect(preview.chapters.first?.lineNumber == 8)
        #expect(preview.chapters.first?.content.hasPrefix("第01篇 第一篇\n正文一") == true)
    }

    @Test("uses chapter headings as file names without numeric prefixes")
    func usesChapterHeadingsAsFileNamesWithoutNumericPrefixes() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        第17篇 原版
        正文
        第17篇 修正版
        修正正文
        第18篇 下一篇
        下一篇正文
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.map(\.heading) == ["第17篇 原版", "第17篇 修正版", "第18篇 下一篇"])
        #expect(preview.chapters.map(\.outputFileName) == [
            "原版.txt",
            "修正版.txt",
            "下一篇.txt"
        ])
    }

    @Test("keeps top level article headings when articles contain internal chapters")
    func keepsTopLevelArticleHeadingsWhenArticlesContainInternalChapters() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        第01篇 第一篇
        正文一
        第一章 内部章节
        内部正文
        第二章 内部章节
        内部正文
        第02篇 第二篇
        正文二
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.map(\.heading) == ["第01篇 第一篇", "第02篇 第二篇"])
        #expect(preview.chapters.first?.content.contains("第一章 内部章节") == true)
    }

    @Test("splits collection files with standalone article titles")
    func splitsCollectionFilesWithStandaloneArticleTitles() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        【文章合集】


        校园观察记录

        第一段正文。


        校园观察记录（1）

        续篇正文。


        连载记录[节选]

        （一）

        内部小节正文。

        （二）

        更多内部正文。
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.map(\.heading) == [
            "校园观察记录",
            "校园观察记录（1）",
            "连载记录[节选]"
        ])
        #expect(preview.chapters.last?.content.contains("（一）") == true)
        #expect(preview.chapters.last?.content.contains("（二）") == true)
    }

    @Test("ignores standalone prose teasers and titled subsection markers")
    func ignoresStandaloneProseTeasersAndTitledSubsectionMarkers() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("合集.txt")
        try """
        第一篇记录

        正文。

        下次继续分享这个记录……


        连载记录

        （一）起因

        小节正文。

        （二）经过

        更多小节正文。


        另一篇记录

        另一篇正文。
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.map(\.heading) == [
            "第一篇记录",
            "连载记录",
            "另一篇记录"
        ])
        #expect(preview.chapters[1].content.contains("（一）起因") == true)
        #expect(preview.chapters[1].content.contains("（二）经过") == true)
    }

    @Test("decodes GB18030 input and writes UTF-8 split files")
    func decodesGB18030AndWritesUTF8Files() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gb18030.txt")
        let text = """
        第01篇 简体中文
        第一段
        第02篇 第二篇
        第二段
        """
        try #require(text.data(using: encoding(named: "GB18030"))).write(to: file)

        let preview = try TextFileSplitService().previewSplit(for: file)
        let created = try TextFileSplitService().split(preview, deleteOriginal: true)

        #expect(preview.detectedEncoding == "gbk")
        #expect(created.count == 2)
        #expect(try String(contentsOf: created[0], encoding: .utf8).contains("第一段"))
        #expect(try String(contentsOf: created[1], encoding: .utf8).contains("第二段"))
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("rejects files without multiple chapter headings")
    func rejectsFilesWithoutMultipleChapterHeadings() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("single.txt")
        try "第01篇 只有一篇\n正文".write(to: file, atomically: true, encoding: .utf8)

        #expect(throws: TextFileSplitError.notEnoughChapters) {
            try TextFileSplitService().previewSplit(for: file)
        }
    }

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
