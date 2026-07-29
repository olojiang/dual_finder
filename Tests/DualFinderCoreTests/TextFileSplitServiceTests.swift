import Foundation
import Testing
@testable import DualFinderCore

private func externalSampleAvailable(at path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

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

    @Test("splits merged file when chapter sequence resets within same unit")
    func splitsMergedFileOnChapterReset() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("merged.txt")
        try """
        第01章 开始
        正文一
        第02章 继续
        正文二
        第03章 发展
        正文三
        第04章 转折
        正文四
        第05章 高潮
        正文五
        第06章 结局
        正文六
        第01章 新故事
        新正文一
        第02章 新故事续
        新正文二
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters[0].content.contains("正文一") == true)
        #expect(preview.chapters[0].content.contains("新故事") == false)
        #expect(preview.chapters[1].content.contains("新正文一") == true)
    }

    @Test("splits merged file when chapter unit changes after a long run")
    func splitsMergedFileOnUnitChange() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("merged.txt")
        try """
        第01节
        正文一
        第02节
        正文二
        第03节
        正文三
        第04节
        正文四
        第05节
        正文五
        第06节
        正文六
        第01章 新故事
        新正文
        第02章 新故事续
        新正文续
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters[0].content.contains("正文一") == true)
        #expect(preview.chapters[0].content.contains("新故事") == false)
        #expect(preview.chapters[1].content.contains("新正文") == true)
    }

    @Test("splits merged file at completion marker between sections")
    func splitsMergedFileOnCompletionMarker() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("merged.txt")
        try """
        第01章 开始
        正文一
        第02章 结束
        正文二
        「全文完」
        第01章 第二个故事
        新正文一
        第02章 第二个故事续
        新正文二
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters[0].content.contains("正文一") == true)
        #expect(preview.chapters[0].content.contains("第二个故事") == false)
        #expect(preview.chapters[1].content.contains("新正文一") == true)
    }

    @Test("parses most granular unit in multi-unit headings")
    func parsesMostGranularUnitInMultiUnitHeadings() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("merged.txt")
        try """
        第一部 第001章 精尽人亡
        正文一
        第一部 第002章 重生
        正文二
        第一部 第003章 继续
        正文三
        第一部 第004章 发展
        正文四
        第一部 第005章 转折
        正文五
        第一部 第006章 高潮
        正文六
        第二部 第001章 新开始
        新正文一
        第二部 第002章 新发展
        新正文二
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters[0].content.contains("正文一") == true)
        #expect(preview.chapters[1].content.contains("新正文一") == true)
    }

    @Test("does not merge single file with nested chapters into separate files")
    func doesNotSplitNestedChaptersInSingleFile() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("single.txt")
        try """
        第01篇 第一篇
        正文一
        第一章 内部章节
        内部正文一
        第二章 内部章节
        内部正文二
        第02篇 第二篇
        正文二
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters.map(\.heading) == ["第01篇 第一篇", "第02篇 第二篇"])
        #expect(preview.chapters[0].content.contains("第一章 内部章节") == true)
    }

    @Test("does not split nested section numbering resets")
    func doesNotSplitNestedSectionNumberingResets() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("nested-sections.txt")
        try """
        第一部 第一章 开始
        正文一
        第一节 起因
        小节正文一
        第二节 经过
        小节正文二
        第二章 继续
        正文二
        第一节 转折
        小节正文三
        第二节 结局
        小节正文四
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters.map(\.heading) == ["第一部 第一章 开始", "第二章 继续"])
    }

    @Test("recognizes a prefixed chapter heading after a completion marker")
    func recognizesPrefixedChapterHeadingAfterCompletionMarker() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("prefixed-heading.txt")
        try """
        第01章 旧故事
        旧正文
        第02章 旧故事续
        旧正文续
        全文完
        新故事 第一章 开始
        新正文
        新故事 第二章 结束
        新正文续
        """.write(to: file, atomically: true, encoding: .utf8)

        let preview = try TextFileSplitService().previewSplit(for: file)

        #expect(preview.chapters.count == 2)
        #expect(preview.chapters[1].heading == "新故事 第一章 开始")
    }

    @Test("splits the provided 31-file merged sample into 31 files", .disabled(if: !externalSampleAvailable(at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/31个合并文件.txt")))
    func splitsProvided31FileSample() throws {
        let file = URL(fileURLWithPath: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/31个合并文件.txt")
        try #require(FileManager.default.fileExists(atPath: file.path))
        let root = try TemporaryDirectory()
        let copiedFile = root.url.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copiedFile)

        let service = TextFileSplitService()
        let preview = try service.previewSplit(for: copiedFile)
        let createdFiles = try service.split(preview)

        #expect(preview.chapters.count == 31)
        #expect(createdFiles.count == 31)
        #expect(createdFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: copiedFile.path) == false)
    }

    @Test("splits a generated 22-document merged sample")
    func splitsGenerated22DocumentSample() throws {
        let root = try TemporaryDirectory()
        let mergedFile = root.url.appendingPathComponent("generated-merged-sample.txt")
        try makeMergedSample(documentCount: 22, chaptersPerDocument: 6)
            .write(to: mergedFile, atomically: true, encoding: .utf8)

        let service = TextFileSplitService()
        let preview = try service.previewSplit(for: mergedFile)
        let createdFiles = try service.split(preview)

        #expect(preview.chapters.count == 22)
        #expect(createdFiles.count == 22)
        #expect(createdFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: mergedFile.path) == false)
        #expect(preview.chapters.first?.heading == "第01章 文档01-章节01")
        #expect(preview.chapters.last?.heading == "第01章 文档22-章节01")
    }

    @Test("splits the provided 35-file merged sample into 35 files", .disabled(if: !externalSampleAvailable(at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/萝莉长篇小说整理合集，共35篇，合1645章.txt")))
    func splitsProvided35FileSample() throws {
        let file = URL(fileURLWithPath: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/萝莉长篇小说整理合集，共35篇，合1645章.txt")
        try #require(FileManager.default.fileExists(atPath: file.path))
        let root = try TemporaryDirectory()
        let copiedFile = root.url.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copiedFile)

        let service = TextFileSplitService()
        let preview = try service.previewSplit(for: copiedFile)
        let createdFiles = try service.split(preview)

        #expect(preview.chapters.count == 35)
        #expect(createdFiles.count == 35)
        #expect(createdFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: copiedFile.path) == false)
    }

    @Test("splits the provided 135-file merged sample into 135 files", .disabled(if: !externalSampleAvailable(at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/h天龙h合集   作者：h天龙h[135篇]最新.txt")))
    func splitsProvided135FileSample() throws {
        try assertProvidedMergedSample(
            at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/h天龙h合集   作者：h天龙h[135篇]最新.txt",
            expectedCount: 135
        )
    }

    @Test("splits the provided 85-file merged sample into 85 files", .disabled(if: !externalSampleAvailable(at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/《父女乱文合集》作者：多人[85篇].txt")))
    func splitsProvided85FileSample() throws {
        try assertProvidedMergedSample(
            at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/《父女乱文合集》作者：多人[85篇].txt",
            expectedCount: 85
        )
    }

    @Test("splits the provided 15-file merged sample into 15 files", .disabled(if: !externalSampleAvailable(at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/《rainy丝袜乱伦作品集》（15篇）作者：rainy [精校完结].txt")))
    func splitsProvided15FileSample() throws {
        try assertProvidedMergedSample(
            at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/《rainy丝袜乱伦作品集》（15篇）作者：rainy [精校完结].txt",
            expectedCount: 15
        )
    }

    @Test("splits the provided 20-file merged sample into 20 files", .disabled(if: !externalSampleAvailable(at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/花间浪子二十部小说.txt")))
    func splitsProvided20FileSample() throws {
        try assertProvidedMergedSample(
            at: "/Volumes/pm9a1_1T/Novel_Android/Novel_Merged/tmp/花间浪子二十部小说.txt",
            expectedCount: 20
        )
    }

    private func assertProvidedMergedSample(at path: String, expectedCount: Int) throws {
        let file = URL(fileURLWithPath: path)
        try #require(FileManager.default.fileExists(atPath: file.path))
        let root = try TemporaryDirectory()
        let copiedFile = root.url.appendingPathComponent(file.lastPathComponent)
        try FileManager.default.copyItem(at: file, to: copiedFile)

        let service = TextFileSplitService()
        let preview = try service.previewSplit(for: copiedFile)
        let createdFiles = try service.split(preview)

        #expect(preview.chapters.count == expectedCount)
        #expect(createdFiles.count == expectedCount)
        #expect(createdFiles.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(FileManager.default.fileExists(atPath: copiedFile.path) == false)
    }

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    private func makeMergedSample(documentCount: Int, chaptersPerDocument: Int) -> String {
        var lines = [
            "合并文件导言",
            "这段前言模拟真实合集中的版权、目录和下载提示。",
            ""
        ]

        for document in 1...documentCount {
            if document > 1 {
                lines.append("全文完")
                lines.append("")
            }

            for chapter in 1...chaptersPerDocument {
                let documentToken = String(format: "%02d", document)
                let chapterToken = String(format: "%02d", chapter)
                lines.append("第\(chapterToken)章 文档\(documentToken)-章节\(chapterToken)")
                lines.append("文档\(documentToken) 的第\(chapterToken) 章正文，包含连续章节和独立段落。")
                lines.append("")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }
}
