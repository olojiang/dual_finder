import Foundation
import Testing
@testable import DualFinderCore

@Suite("TextEncodingConversionService")
struct TextEncodingConversionServiceTests {
    @Test("keeps UTF-8 files unchanged")
    func keepsUTF8FilesUnchanged() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf8.txt")
        try "plain utf-8 中文".write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8")
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == "plain utf-8 中文")
    }

    @Test("keeps UTF-8 files with private-use glyphs unchanged")
    func keepsUTF8FilesWithPrivateUseGlyphsUnchanged() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf8-private-use.txt")
        let sourceText = "请各位记住地址\n" + String(repeating: "\u{e4c6}", count: 6) + "\n正文继续，章节内容保持原样，人物对话和段落排版都应该保留。"
        try sourceText.write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("converts GBK files to UTF-8 in place")
    func convertsGBKFilesToUTF8InPlace() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gbk.txt")
        let sourceText = "简体中文 GBK"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "gbk")
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("repairs GBK text containing limited NUL bytes")
    func repairsGBKTextContainingLimitedNULBytes() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gbk-nul.txt")
        let sourceText = "书名：妻毒\n作者：三臭\n正文继续"
        var data = try #require(sourceText.data(using: encoding(named: "GBK")))
        data.append(0)
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "gbk-repaired-nul")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("repairs UTF-8 text with NUL padding")
    func repairsUTF8TextWithNULPadding() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf8-padded.txt")
        let sourceText = "请各位记住永久地址\n正文继续\n"
        var data = Data(sourceText.utf8)
        data.append(Data(repeating: 0, count: 2048))
        let logger = CapturingLogger()
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: logger).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "utf-8-repaired-nul-padding")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
        #expect(logger.messages.contains { $0.contains("removedNULBytes") })
    }

    @Test("converts GBK text that contains common private-use glyphs")
    func convertsGBKTextThatContainsCommonPrivateUseGlyphs() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gbk-private-use.txt")
        let sourceText = "爱\u{e4c6}\u{e4c6}我今年十六歲是一個遺腹子，父親和母親結婚一個月後便去歐洲出差，在回程的時候卻不幸發生空難。"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "gbk")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("repairs mixed GBK and UTF-8 line encoded text")
    func repairsMixedGBKAndUTF8LineEncodedText() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mixed.txt")
        var data = Data()
        data.append(try #require("请各位记住地址\n".data(using: encoding(named: "GBK"))))
        data.append(try #require("这是南部一个村子里的故事。\n".data(using: .utf8)))

        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "mixed:utf-8+gbk")
        #expect(try String(contentsOf: file, encoding: .utf8) == "请各位记住地址\n这是南部一个村子里的故事。\n")
    }

    @Test("repairs mostly decodable mixed text with sparse corrupt bytes")
    func repairsMostlyDecodableMixedTextWithSparseCorruptBytes() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mixed-sparse-corrupt.txt")
        var data = Data()
        var expected = ""
        for _ in 0..<40 {
            data.append(try #require("看更多上电报加入免费小说频道\n".data(using: .utf8)))
            data.append(try #require("序章家族成员\n".data(using: encoding(named: "GB18030"))))
            expected += "看更多上电报加入免费小说频道\n序章家族成员\n"
        }
        data.append(Data([0xff, 0xfe, 0xfd, 0x0a]))
        data.append(try #require("正文继续\n".data(using: .utf8)))
        expected += "���\n正文继续\n"
        let logger = CapturingLogger()
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: logger).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "mixed:utf-8+gbk+utf-8-lossy")
        #expect(try String(contentsOf: file, encoding: .utf8) == expected)
        #expect(logger.messages.contains { $0.contains("lossyByteCount") })
    }

    @Test("restores original name when marked unknown files are recovered")
    func restoresOriginalNameWhenMarkedUnknownFilesAreRecovered() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gbk.txt_unknown_encode_unknown_encode")
        let sourceText = "简体中文 GBK"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)
        let restored = root.url.appendingPathComponent("gbk.txt")

        #expect(result.status == .converted)
        #expect(result.finalURL == restored.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: restored, encoding: .utf8) == sourceText)
    }

    @Test("restores recovered files from unknown directory")
    func restoresRecoveredFilesFromUnknownDirectory() throws {
        let root = try TemporaryDirectory()
        let unknownDirectory = root.url.appendingPathComponent("unknown_encode", isDirectory: true)
        try FileManager.default.createDirectory(at: unknownDirectory, withIntermediateDirectories: true)
        let file = unknownDirectory.appendingPathComponent("gbk.txt")
        let sourceText = "简体中文 GBK"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)
        let restored = root.url.appendingPathComponent("gbk.txt")

        #expect(result.status == .converted)
        #expect(result.finalURL == restored.standardizedFileURL)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(try String(contentsOf: restored, encoding: .utf8) == sourceText)
    }

    @Test("converts Big5 files to UTF-8 in place")
    func convertsBig5FilesToUTF8InPlace() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("big5.txt")
        let sourceText = "繁體中文 Big5"
        try #require(sourceText.data(using: encoding(named: "Big5"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "big5")
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("converts lossy GB18030 files when most text is readable")
    func convertsLossyGB18030FilesWhenMostTextIsReadable() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gb18030-lossy.txt")
        var data = try #require("<风流花少>\n作者：星雨寻找\n我叫花睿龙，今年10岁。\n".data(using: encoding(named: "GB18030")))
        data.append(contentsOf: [0xff, 0xfe, 0xfd])
        data.append(try #require("\n正文继续。".data(using: encoding(named: "GB18030"))))
        let logger = CapturingLogger()
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: logger).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "gb18030-lossy")
        #expect(try String(contentsOf: file, encoding: .utf8).contains("我叫花睿龙"))
        #expect(logger.messages.contains { $0.contains("lossyByteCount") })
    }

    @Test("converts UTF-16 files to UTF-8 in place")
    func convertsUTF16FilesToUTF8InPlace() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf16.txt")
        let sourceText = "UTF-16 text 中文"
        try #require(sourceText.data(using: .utf16LittleEndian)).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "utf-16le")
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("moves files when encoding cannot be identified")
    func movesUnknownEncodingFiles() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("binary.txt")
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)
        let logger = CapturingLogger()

        let result = try TextEncodingConversionService(logger: logger).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.detectedEncoding == nil)
        #expect(result.diagnostic == "contains NUL bytes and does not look like supported text")
        #expect(result.finalURL.lastPathComponent == "binary.txt")
        #expect(result.finalURL.deletingLastPathComponent().lastPathComponent == "unknown_encode")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: result.finalURL.path))
        #expect(logger.messages.contains { $0.contains("sampleHex") && $0.contains("reason") })
    }

    @Test("rejects pure NUL files as unknown")
    func rejectsPureNULFilesAsUnknown() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("pure-nul.txt")
        try Data(repeating: 0, count: 4096).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
    }

    @Test("repairs UTF-16 LE files with orphan high surrogate")
    func repairsUTF16LEFilesWithOrphanHighSurrogate() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf16-orphan-high.txt")
        // UTF-16 LE BOM + "晓故事" + orphan high surrogate U+D800 + "正文"
        var data = Data([0xff, 0xfe])
        data.append(contentsOf: [0x53, 0x66, 0x45, 0x65, 0x8b, 0x4e])  // 晓故事
        data.append(contentsOf: [0x00, 0xd8])                          // orphan high surrogate
        data.append(contentsOf: [0x63, 0x6b, 0x87, 0x65])              // 正文
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-16le") == true)
        let converted = try String(contentsOf: file, encoding: .utf8)
        #expect(converted.contains("晓故事"))
        #expect(converted.contains("正文"))
        #expect(!converted.contains("\u{fffd}"))
    }

    @Test("repairs UTF-16 LE files with orphan low surrogate")
    func repairsUTF16LEFilesWithOrphanLowSurrogate() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf16-orphan-low.txt")
        // UTF-16 LE BOM + "标题" + orphan low surrogate U+DE62 + "内容"
        var data = Data([0xff, 0xfe])
        data.append(contentsOf: [0x00, 0x6d, 0x98, 0x98])              // 标题 (U+6D00, U+9898)
        data.append(contentsOf: [0x62, 0xde])                          // orphan low surrogate
        data.append(contentsOf: [0x4e, 0x53, 0x39, 0x5b])              // 内容 (U+534E, U+5B39)
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-16le") == true)
        let converted = try String(contentsOf: file, encoding: .utf8)
        #expect(!converted.contains("\u{fffd}"))
    }

    @Test("preserves valid UTF-16 LE surrogate pairs (emoji)")
    func preservesValidUTF16LESurrogatePairs() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf16-emoji.txt")
        // UTF-16 LE BOM + "emoji " + U+1F600 (grinning face, surrogate pair D83D DE00) + " text"
        var data = Data([0xff, 0xfe])
        let prefix = "emoji "
        for scalar in prefix.unicodeScalars {
            let v = UInt16(scalar.value)
            data.append(UInt8(v & 0xff))
            data.append(UInt8(v >> 8))
        }
        data.append(contentsOf: [0x3d, 0xd8, 0x00, 0xde])              // U+1F600 as surrogate pair
        let suffix = " text"
        for scalar in suffix.unicodeScalars {
            let v = UInt16(scalar.value)
            data.append(UInt8(v & 0xff))
            data.append(UInt8(v >> 8))
        }
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-16le") == true)
        let converted = try String(contentsOf: file, encoding: .utf8)
        #expect(converted.contains("emoji"))
        #expect(converted.contains("\u{1f600}"))
        #expect(converted.contains("text"))
    }

    @Test("repairs UTF-16 LE file with massive orphan surrogates from real-world corruption")
    func repairsUTF16LEFileWithMassiveOrphanSurrogates() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf16-corrupted.txt")
        // Simulate real-world PP_Novel_Download corruption: many orphan surrogates
        // interspersed with readable text. Files in unknown_encode/ have ~5% orphan
        // surrogates which previously caused textLooksReadable to reject them.
        var data = Data([0xff, 0xfe])
        let line = "正文行内容继续测试，这是中文字符。\n"
        for _ in 0..<50 {
            for scalar in line.unicodeScalars {
                let v = UInt16(scalar.value)
                data.append(UInt8(v & 0xff))
                data.append(UInt8(v >> 8))
            }
            // Insert 3 orphan surrogates per line (~5% corruption rate)
            data.append(contentsOf: [0x00, 0xd8])  // orphan high surrogate
            data.append(contentsOf: [0x62, 0xde])  // orphan low surrogate
            data.append(contentsOf: [0x01, 0xd9])  // orphan high surrogate
        }
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-16le") == true)
        let converted = try String(contentsOf: file, encoding: .utf8)
        #expect(converted.contains("正文行内容继续测试"))
        // Orphan surrogates should be dropped, not converted to U+FFFD
        #expect(!converted.contains("\u{fffd}"))
    }

    @Test("skips AppleDouble metadata files without moving to unknown_encode")
    func skipsAppleDoubleMetadataFilesWithoutMoving() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("._novel.txt")
        // AppleDouble header magic: 00 05 16 07
        var data = Data([0x00, 0x05, 0x16, 0x07])
        data.append(Data(repeating: 0, count: 100))
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .skipped)
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: file.path))
        let unknownDir = root.url.appendingPathComponent("unknown_encode")
        #expect(!FileManager.default.fileExists(atPath: unknownDir.path))
    }

    @Test("converts UTF-16 BE files to UTF-8")
    func convertsUTF16BEFilesToUTF8() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf16be.txt")
        let sourceText = "UTF-16 BE 繁體中文"
        var data = Data([0xfe, 0xff])
        data.append(try #require(sourceText.data(using: .utf16BigEndian)))
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.contains("utf-16") == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("diagnoses RAR archive files with text extensions")
    func diagnosesRARArchiveFilesWithTextExtensions() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("archive.txt")
        try Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x00, 0x00]).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.diagnostic == "looks like a RAR archive, not a text file")
    }

    @Test("diagnoses archive files with text extensions")
    func diagnosesArchiveFilesWithTextExtensions() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("archive.txt")
        try Data([0x50, 0x4b, 0x03, 0x04, 0x14, 0x00, 0x00, 0x00]).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.diagnostic == "looks like a ZIP archive, not a text file")
    }

    @Test("uses a unique unknown directory destination")
    func usesUniqueUnknownDirectoryDestination() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("binary.txt")
        let unknownDirectory = root.url.appendingPathComponent("unknown_encode", isDirectory: true)
        try FileManager.default.createDirectory(at: unknownDirectory, withIntermediateDirectories: true)
        let existing = unknownDirectory.appendingPathComponent("binary.txt")
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)
        try Data().write(to: existing)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.finalURL.lastPathComponent == "binary.txt 2")
        #expect(result.finalURL.deletingLastPathComponent() == unknownDirectory.standardizedFileURL)
    }

    @Test("does not move files already in unknown directory again")
    func doesNotMoveFilesAlreadyInUnknownDirectoryAgain() throws {
        let root = try TemporaryDirectory()
        let unknownDirectory = root.url.appendingPathComponent("unknown_encode", isDirectory: true)
        try FileManager.default.createDirectory(at: unknownDirectory, withIntermediateDirectories: true)
        let file = unknownDirectory.appendingPathComponent("binary.txt")
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: unknownDirectory.appendingPathComponent("unknown_encode").path))
    }

    @Test("skips common non-text formats without renaming")
    func skipsCommonNonTextFormatsWithoutRenaming() throws {
        let root = try TemporaryDirectory()
        let files = ["cover.jpg", "book.epub", "song.mp3"].map { root.url.appendingPathComponent($0) }
        for file in files {
            try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)
        }

        let service = TextEncodingConversionService(logger: CapturingLogger())
        let result = try service.convertFilesToUTF8(files)

        #expect(result.results.map(\.status) == [.skipped, .skipped, .skipped])
        #expect(result.skippedCount == 3)
        for file in files {
            #expect(FileManager.default.fileExists(atPath: file.path))
            let unknownName = file.lastPathComponent + "_unknown_encode"
            #expect(!FileManager.default.fileExists(atPath: root.url.appendingPathComponent(unknownName).path))
            #expect(try service.detectFileEncoding(file) == nil)
        }
    }

    @Test("skips directories")
    func skipsDirectories() throws {
        let root = try TemporaryDirectory()
        let folder = root.url.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(folder)

        #expect(result.status == .skipped)
        #expect(result.finalURL == folder.standardizedFileURL)
    }

    @Test("reports batch progress after each file")
    func reportsBatchProgressAfterEachFile() throws {
        let root = try TemporaryDirectory()
        let first = root.url.appendingPathComponent("first.txt")
        let second = root.url.appendingPathComponent("second.txt")
        try "first".write(to: first, atomically: true, encoding: .utf8)
        try "second".write(to: second, atomically: true, encoding: .utf8)
        var progress: [(Int, Int, URL, TextEncodingConversionStatus)] = []

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFilesToUTF8([first, second]) { completedCount, totalCount, fileResult in
            progress.append((completedCount, totalCount, fileResult.finalURL, fileResult.status))
        }

        #expect(result.results.count == 2)
        #expect(progress.map(\.0) == [1, 2])
        #expect(progress.map(\.1) == [2, 2])
        #expect(progress.map(\.2) == [first.standardizedFileURL, second.standardizedFileURL])
        #expect(progress.map(\.3) == [.alreadyUTF8, .alreadyUTF8])
    }

    @Test("convertFilesToUTF8 aborts remaining files after cancellation")
    func convertFilesToUTF8AbortsAfterCancellation() throws {
        let root = try TemporaryDirectory()
        var files: [URL] = []
        for index in 0..<5 {
            let url = root.url.appendingPathComponent("file-\(index).txt")
            try "content-\(index)".write(to: url, atomically: true, encoding: .utf8)
            files.append(url)
        }

        let cancellation = FileOperationCancellation()
        var processedCount = 0
        #expect(throws: FileOperationError.cancelled) {
            _ = try TextEncodingConversionService(logger: CapturingLogger()).convertFilesToUTF8(
                files,
                cancellation: cancellation,
                progress: { _, _, _ in
                    processedCount += 1
                    if processedCount == 2 {
                        cancellation.cancel()
                    }
                }
            )
        }

        #expect(processedCount == 2)
    }

    @Test("batch conversion continues after a file failure")
    func batchConversionContinuesAfterFileFailure() throws {
        let root = try TemporaryDirectory()
        let unreadable = root.url.appendingPathComponent("unreadable.txt")
        let valid = root.url.appendingPathComponent("valid.txt")
        try "unreadable".write(to: unreadable, atomically: true, encoding: .utf8)
        try "valid".write(to: valid, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: unreadable.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: unreadable.path)
        }

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFilesToUTF8([unreadable, valid])

        #expect(result.results.map(\.status) == [.failed, .alreadyUTF8])
        #expect(result.failedCount == 1)
        #expect(result.failedResults.first?.originalURL == unreadable.standardizedFileURL)
        #expect(result.results.last?.originalURL == valid.standardizedFileURL)
    }

    @Test("caches known UTF-8 files by size and modification date")
    func cachesKnownUTF8FilesBySizeAndModificationDate() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf8.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        try "abcd".write(to: file, atomically: true, encoding: .utf8)

        let first = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let originalModifiedAt = try #require(attributes[.modificationDate] as? Date)
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedAt], ofItemAtPath: file.path)

        let second = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)

        #expect(first.usedCache == false)
        #expect(second.status == .alreadyUTF8)
        #expect(second.detectedEncoding == "utf-8")
        #expect(second.usedCache)
        #expect(FileManager.default.fileExists(atPath: file.path))
        #expect(!FileManager.default.fileExists(atPath: root.url.appendingPathComponent("utf8.txt_unknown_encode").path))
    }

    @Test("updates UTF-8 cache after conversion")
    func updatesUTF8CacheAfterConversion() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gbk.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let sourceText = "简体中文 GBK"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let converted = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)
        let cached = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)

        #expect(converted.status == .converted)
        #expect(cached.status == .alreadyUTF8)
        #expect(cached.usedCache)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("UTF-8 cache key follows file name size and modification date")
    func utf8CacheKeyFollowsFileNameSizeAndModificationDate() throws {
        let root = try TemporaryDirectory()
        let firstDirectory = root.url.appendingPathComponent("first", isDirectory: true)
        let secondDirectory = root.url.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: firstDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondDirectory, withIntermediateDirectories: true)
        let first = firstDirectory.appendingPathComponent("same.txt")
        let second = secondDirectory.appendingPathComponent("same.txt")
        let differentName = secondDirectory.appendingPathComponent("other.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let modifiedAt = Date(timeIntervalSince1970: 1_800)
        try "abcd".write(to: first, atomically: true, encoding: .utf8)
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: second)
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: differentName)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: first.path)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: second.path)
        try FileManager.default.setAttributes([.modificationDate: modifiedAt], ofItemAtPath: differentName.path)

        _ = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(first)
        let sameNameResult = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(second)
        let differentNameResult = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(differentName)

        #expect(sameNameResult.status == .alreadyUTF8)
        #expect(sameNameResult.usedCache)
        #expect(differentNameResult.status == .renamedUnknown)
        #expect(!differentNameResult.usedCache)
    }

    @Test("reads legacy path based encoding cache entries")
    func readsLegacyPathBasedEncodingCacheEntries() throws {
        struct LegacyEntry: Codable {
            var size: Int64
            var modifiedAt: Date
            var encoding: String
        }

        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("legacy.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        try "legacy".write(to: file, atomically: true, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = try #require((attributes[.size] as? NSNumber)?.int64Value)
        let modifiedAt = try #require(attributes[.modificationDate] as? Date)
        let legacy = [file.standardizedFileURL.path: LegacyEntry(size: size, modifiedAt: modifiedAt, encoding: "utf-8")]
        try JSONEncoder().encode(legacy).write(to: cacheURL)

        let result = try TextEncodingConversionService(
            logger: CapturingLogger(),
            cache: TextEncodingConversionCache(storageURL: cacheURL)
        ).convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.usedCache)
        #expect(result.detectedEncoding == "utf-8")
    }

    @Test("markEncoding skips redundant disk writes")
    func markEncodingSkipsRedundantDiskWrites() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let file = root.url.appendingPathComponent("utf8.txt")
        try "abcd".write(to: file, atomically: true, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = try #require((attributes[.size] as? NSNumber)?.int64Value)
        let modifiedAt = try #require(attributes[.modificationDate] as? Date)

        try cache.markUTF8(for: file, size: size, modifiedAt: modifiedAt)
        let firstWrite = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date
        try cache.markUTF8(for: file, size: size, modifiedAt: modifiedAt)
        let secondWrite = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date

        #expect(firstWrite != nil)
        #expect(secondWrite == firstWrite)
    }

    @Test("batch conversion defers cache persistence until completion")
    func batchConversionDefersCachePersistenceUntilCompletion() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let files = (0..<8).map { root.url.appendingPathComponent("file-\($0).txt") }
        for file in files {
            try "content".write(to: file, atomically: true, encoding: .utf8)
        }

        let service = TextEncodingConversionService(logger: CapturingLogger(), cache: cache)
        _ = try service.convertFilesToUTF8(files)

        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
        let persisted = try JSONDecoder().decode([String: CacheProbeEntry].self, from: Data(contentsOf: cacheURL))
        #expect(persisted.count == files.count)
    }

    @Test("batch progress throttles cached UTF-8 hits")
    func batchProgressThrottlesCachedUTF8Hits() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let files = (0..<130).map { root.url.appendingPathComponent("cached-\($0).txt") }
        for file in files {
            try "cached".write(to: file, atomically: true, encoding: .utf8)
        }

        let warmUpService = TextEncodingConversionService(logger: CapturingLogger(), cache: cache)
        _ = try warmUpService.convertFilesToUTF8(files)

        var progressCount = 0
        _ = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFilesToUTF8(files) { _, _, _ in
            progressCount += 1
        }

        #expect(progressCount == 3)
        #expect(TextEncodingConversionService.shouldReportBatchProgress(
            result: TextEncodingConversionResult(
                originalURL: files[0],
                finalURL: files[0],
                detectedEncoding: "utf-8",
                status: .alreadyUTF8,
                usedCache: true
            ),
            completedCount: 64,
            totalCount: 130
        ))
        #expect(!TextEncodingConversionService.shouldReportBatchProgress(
            result: TextEncodingConversionResult(
                originalURL: files[0],
                finalURL: files[0],
                detectedEncoding: "utf-8",
                status: .alreadyUTF8,
                usedCache: true
            ),
            completedCount: 63,
            totalCount: 130
        ))
    }

    @Test("fingerprint cache hit does not require migration mark")
    func fingerprintCacheHitDoesNotRequireMigrationMark() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf8.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        try "abcd".write(to: file, atomically: true, encoding: .utf8)

        _ = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)
        let firstWrite = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date

        _ = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)
        let secondWrite = try FileManager.default.attributesOfItem(atPath: cacheURL.path)[.modificationDate] as? Date

        #expect(firstWrite != nil)
        #expect(secondWrite == firstWrite)
    }

    @Test("legacy cache hit migrates fingerprint entry once")
    func legacyCacheHitMigratesFingerprintEntryOnce() throws {
        struct LegacyEntry: Codable {
            var size: Int64
            var modifiedAt: Date
            var encoding: String
        }

        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("legacy.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        try "legacy".write(to: file, atomically: true, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let size = try #require((attributes[.size] as? NSNumber)?.int64Value)
        let modifiedAt = try #require(attributes[.modificationDate] as? Date)
        let legacy = [file.standardizedFileURL.path: LegacyEntry(size: size, modifiedAt: modifiedAt, encoding: "utf-8")]
        try JSONEncoder().encode(legacy).write(to: cacheURL)

        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let lookup = try #require(cache.lookupEncoding(for: file, size: size, modifiedAt: modifiedAt))
        #expect(lookup.encoding == "utf-8")
        #expect(lookup.needsMigration)

        _ = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache).convertFileToUTF8(file)
        let migratedLookup = try #require(cache.lookupEncoding(for: file, size: size, modifiedAt: modifiedAt))
        #expect(migratedLookup.encoding == "utf-8")
        #expect(!migratedLookup.needsMigration)
    }

    @Test("cached UTF-8 files skip per-file info logging")
    func cachedUTF8FilesSkipPerFileInfoLogging() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let files = (0..<4).map { root.url.appendingPathComponent("cached-\($0).txt") }
        for file in files {
            try "cached".write(to: file, atomically: true, encoding: .utf8)
        }

        let warmUpService = TextEncodingConversionService(logger: CapturingLogger(), cache: cache)
        _ = try warmUpService.convertFilesToUTF8(files)

        let logger = CapturingLogger()
        let result = try TextEncodingConversionService(logger: logger, cache: cache).convertFilesToUTF8(files)

        #expect(result.cachedUTF8Count == files.count)
        #expect(!logger.messages.contains { $0.contains("file.cache-hit") })
        #expect(logger.messages.contains { $0.contains("batch.cache-hits") })
    }

    @Test("detects and caches file list encoding by size and modification date")
    func detectsAndCachesEncodingForFileList() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("gbk.txt")
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let sourceText = "简体中文 GBK"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let service = TextEncodingConversionService(logger: CapturingLogger(), cache: cache)
        let detected = try service.detectFileEncoding(file)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let originalModifiedAt = try #require(attributes[.modificationDate] as? Date)
        let originalSize = try #require(attributes[.size] as? NSNumber).intValue
        try Data(repeating: 0xff, count: originalSize).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: originalModifiedAt], ofItemAtPath: file.path)

        let cached = try service.detectFileEncoding(file)

        #expect(detected == "gbk")
        #expect(cached == "gbk")
    }

    @Test("encoding cache stays unloaded until first lookup")
    func encodingCacheStaysUnloadedUntilFirstLookup() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let file = root.url.appendingPathComponent("sample.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modifiedAt = try #require(attributes[.modificationDate] as? Date)
        let size = Int64(try #require(attributes[.size] as? NSNumber).intValue)

        let payload = [
            file.standardizedFileURL.path: CacheProbeEntry(
                size: size,
                modifiedAt: modifiedAt,
                encoding: "utf-8"
            )
        ]
        try JSONEncoder().encode(payload).write(to: cacheURL)

        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        #expect(cache.isLoadedInMemory == false)
        #expect(cache.entryCount == 0)

        let encoding = cache.cachedEncoding(for: file, size: size, modifiedAt: modifiedAt)
        #expect(encoding == "utf-8")
        #expect(cache.isLoadedInMemory == true)
        #expect(cache.entryCount == 1)
    }

    @Test("encoding cache can release loaded entries when idle")
    func encodingCacheCanReleaseLoadedEntriesWhenIdle() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let file = root.url.appendingPathComponent("sample.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modifiedAt = try #require(attributes[.modificationDate] as? Date)
        let size = Int64(try #require(attributes[.size] as? NSNumber).intValue)

        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        try cache.markEncoding("utf-8", for: file, size: size, modifiedAt: modifiedAt)
        #expect(cache.isLoadedInMemory == true)

        cache.releaseLoadedEntries()
        #expect(cache.isLoadedInMemory == false)
        #expect(cache.entryCount == 0)
    }

    @Test("encoding cache compacts oversized on-disk storage")
    func encodingCacheCompactsOversizedOnDiskStorage() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        var oversized: [String: CacheProbeEntry] = [:]
        for index in 0..<12 {
            oversized["key-\(index)"] = CacheProbeEntry(size: 1, modifiedAt: Date(), encoding: "utf-8")
        }
        try JSONEncoder().encode(oversized).write(to: cacheURL)

        let cache = TextEncodingConversionCache(storageURL: cacheURL, maxEntries: 5)
        let result = try #require(try cache.compactStorageIfNeeded())
        #expect(result.before == 12)
        #expect(result.after == 5)
        #expect(cache.isLoadedInMemory == false)
        #expect(cache.entryCount == 0)

        let reloaded = TextEncodingConversionCache(storageURL: cacheURL, maxEntries: 5)
        _ = reloaded.cachedEncoding(
            for: URL(fileURLWithPath: "/tmp/file.txt"),
            size: 1,
            modifiedAt: Date()
        )
        #expect(reloaded.entryCount <= 5)
    }

    @Test("encoding cache trims to max entries")
    func encodingCacheTrimsToMaxEntries() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL, maxEntries: 3)
        let modifiedAt = Date()

        for index in 0..<5 {
            let file = root.url.appendingPathComponent("file-\(index).txt")
            try "sample".write(to: file, atomically: true, encoding: .utf8)
            try cache.markEncoding("utf-8", for: file, size: 6, modifiedAt: modifiedAt)
        }

        #expect(cache.entryCount == 3)
        let newest = root.url.appendingPathComponent("file-4.txt")
        #expect(cache.cachedEncoding(for: newest, size: 6, modifiedAt: modifiedAt) == "utf-8")
        let oldest = root.url.appendingPathComponent("file-0.txt")
        #expect(cache.cachedEncoding(for: oldest, size: 6, modifiedAt: modifiedAt) == nil)
    }

    // MARK: - Fix 1: cache release after batch conversion

    @Test("convertFilesToUTF8 releases cache entries after batch completion")
    func convertFilesToUTF8ReleasesCacheEntriesAfterBatch() throws {
        let root = try TemporaryDirectory()
        let cacheURL = root.url.appendingPathComponent("encoding-cache.json")
        let cache = TextEncodingConversionCache(storageURL: cacheURL)
        let file = root.url.appendingPathComponent("utf8.txt")
        try "hello".write(to: file, atomically: true, encoding: .utf8)

        let service = TextEncodingConversionService(logger: CapturingLogger(), cache: cache)
        _ = try service.convertFilesToUTF8([file])

        #expect(cache.isLoadedInMemory == false)
        #expect(cache.entryCount == 0)
        #expect(FileManager.default.fileExists(atPath: cacheURL.path))
    }

    // MARK: - Fix 2: autoreleasepool in batch loop

    @Test("batch conversion handles many mixed-encoding files correctly")
    func batchConversionHandlesManyMixedEncodingFiles() throws {
        let root = try TemporaryDirectory()
        let files = (0..<60).map { index -> URL in
            let url = root.url.appendingPathComponent("file-\(index).txt")
            if index.isMultiple(of: 2) {
                try? "utf8 content \(index) 中文".write(to: url, atomically: true, encoding: .utf8)
            } else {
                let text = "gbk content \(index) 简体"
                try? text.data(using: encoding(named: "GBK"))?.write(to: url)
            }
            return url
        }

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFilesToUTF8(files)

        #expect(result.results.count == 60)
        #expect(result.convertedCount == 30)
        #expect(result.alreadyUTF8Count == 30)
        #expect(result.failedCount == 0)
        for file in files {
            #expect(try String(contentsOf: file, encoding: .utf8).contains("content"))
        }
    }

    // MARK: - Fix 3: streaming UTF-8 validation

    @Test("preserves valid UTF-8 files with irreversible mojibake markers")
    func preservesValidUTF8FilesWithIrreversibleMojibakeMarkers() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("utf8-lossy-content.txt")
        let sourceText = "正常中文内容\n损坏片段：\u{fffd}\u{e4c6}\n后续内容仍然是 UTF-8。"
        try sourceText.write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8-lossy")
        #expect(result.finalURL == file.standardizedFileURL)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("caches readable lossy UTF-8 classification without rereading the file")
    func cachesReadableLossyUTF8Classification() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("cached-utf8-lossy-content.txt")
        let cache = TextEncodingConversionCache(storageURL: root.url.appendingPathComponent("cache.json"))
        let sourceText = String(repeating: "中文正文可读内容\n", count: 20)
            + "不可逆：\u{fffd}\u{e4c6}\n"
        try sourceText.write(to: file, atomically: true, encoding: .utf8)
        var fullFileLoadCount = 0

        let first = try TextEncodingConversionService(
            logger: CapturingLogger(),
            cache: cache,
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            }
        ).convertFileToUTF8(file)
        #expect(first.detectedEncoding == "utf-8-lossy")

        fullFileLoadCount = 0
        let second = try TextEncodingConversionService(
            logger: CapturingLogger(),
            cache: cache,
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            }
        ).convertFileToUTF8(file)

        #expect(second.status == .alreadyUTF8)
        #expect(second.usedCache)
        #expect(fullFileLoadCount == 0)
    }

    @Test("clean UTF-8 conversion does not load the whole file")
    func cleanUTF8ConversionAvoidsFullFileLoad() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("streamed-utf8.txt")
        let content = String(repeating: "这是一行干净的 UTF-8 内容。\n", count: 10_000)
        try content.write(to: file, atomically: true, encoding: .utf8)
        var fullFileLoadCount = 0
        let service = TextEncodingConversionService(
            logger: CapturingLogger(),
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            }
        )

        let result = try service.convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8")
        #expect(fullFileLoadCount == 0)
    }

    @Test("cached clean UTF-8 conversion does not load the whole file")
    func cachedCleanUTF8ConversionAvoidsFullFileLoad() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("cached-streamed-utf8.txt")
        let cache = TextEncodingConversionCache(storageURL: root.url.appendingPathComponent("cache.json"))
        try String(repeating: "cached UTF-8 内容\n", count: 10_000)
            .write(to: file, atomically: true, encoding: .utf8)
        _ = try TextEncodingConversionService(logger: CapturingLogger(), cache: cache)
            .convertFileToUTF8(file)
        var fullFileLoadCount = 0
        let service = TextEncodingConversionService(
            logger: CapturingLogger(),
            cache: cache,
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            }
        )

        let result = try service.convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.usedCache)
        #expect(fullFileLoadCount == 0)
    }

    @Test("suspicious UTF-8 scalar crossing a stream chunk boundary uses full inspection")
    func suspiciousUTF8ScalarAcrossChunkBoundaryUsesFullInspection() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("chunk-boundary-marker.txt")
        let content = String(repeating: "a", count: 65_535) + "\u{fffd}\n正常中文内容"
        try content.write(to: file, atomically: true, encoding: .utf8)
        var fullFileLoadCount = 0
        let service = TextEncodingConversionService(
            logger: CapturingLogger(),
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            }
        )

        let result = try service.convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(fullFileLoadCount == 1)
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
    }

    @Test("control-heavy UTF-8 data does not use the text fast path")
    func controlHeavyUTF8DataUsesFullInspection() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("control-heavy.txt")
        let content = String(repeating: "\u{0001}", count: 100) + "plain text"
        try content.write(to: file, atomically: true, encoding: .utf8)
        var fullFileLoadCount = 0
        let service = TextEncodingConversionService(
            logger: CapturingLogger(),
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            }
        )

        let result = try service.convertFileToUTF8(file)

        #expect(fullFileLoadCount == 1)
        #expect(result.status == .renamedUnknown)
    }

    @Test("stream read failure falls back to full inspection")
    func streamReadFailureUsesFullInspection() throws {
        enum ProbeError: Error { case readFailed }

        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("read-failure.txt")
        try String(repeating: "valid UTF-8 中文\n", count: 10_000)
            .write(to: file, atomically: true, encoding: .utf8)
        var streamReadCount = 0
        var fullFileLoadCount = 0
        let service = TextEncodingConversionService(
            logger: CapturingLogger(),
            loadFullFileData: { url in
                fullFileLoadCount += 1
                return try Data(contentsOf: url)
            },
            readStreamingChunk: { handle, chunkSize in
                streamReadCount += 1
                guard streamReadCount == 1 else { throw ProbeError.readFailed }
                return try handle.read(upToCount: chunkSize) ?? Data()
            }
        )

        let result = try service.convertFileToUTF8(file)

        #expect(streamReadCount == 2)
        #expect(fullFileLoadCount == 1)
        #expect(result.status == .alreadyUTF8)
    }

    @Test("large UTF-8 file is detected as already UTF-8")
    func largeUTF8FileDetectedAsAlreadyUTF8() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("large-utf8.txt")
        let line = "这是一行中文内容，用于测试大文件的 UTF-8 检测。\n"
        let content = String(repeating: line, count: 10_000)
        try content.write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8")
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
    }

    @Test("large GBK file is converted correctly via fallback")
    func largeGBKFileConvertedViaFallback() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("large-gbk.txt")
        let line = "简体中文内容测试行\n"
        let content = String(repeating: line, count: 10_000)
        try #require(content.data(using: encoding(named: "GBK"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "gbk")
        #expect(try String(contentsOf: file, encoding: .utf8) == content)
    }

    @Test("large UTF-8 file with NUL bytes falls back to full read")
    func largeUTF8WithNULBytesFallsBackToFullRead() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("large-utf8-nul.txt")
        var data = Data(String(repeating: "中文内容\n", count: 10_000).utf8)
        data.append(Data(repeating: 0, count: 2048))
        try data.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        // NUL bytes cause streaming fast path to be skipped; full-read path repairs and converts
        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-8") == true)
        // File should no longer contain NUL bytes after conversion
        let convertedData = try Data(contentsOf: file)
        #expect(!convertedData.contains(0))
    }

    @Test("detectFileEncoding returns utf-8 for large UTF-8 file")
    func detectFileEncodingReturnsUTF8ForLargeFile() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("large-detect.txt")
        let content = String(repeating: "检测编码内容行\n", count: 10_000)
        try content.write(to: file, atomically: true, encoding: .utf8)

        let encoding = try TextEncodingConversionService(logger: CapturingLogger()).detectFileEncoding(file)

        #expect(encoding == "utf-8")
    }

    private struct CacheProbeEntry: Codable {
        var size: Int64
        var modifiedAt: Date
        var encoding: String
    }

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }

    // MARK: - Force re-convert / mojibake repair

    @Test("force re-convert repairs UTF-8 mojibake from GBK via latin-1")
    func forceReconvertRepairsMojibakeFromGBKViaLatin1() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mojibake-gbk.txt")
        let sourceText = "简体中文内容测试，验证 mojibake 修复功能。"
        let gbkBytes = try #require(sourceText.data(using: encoding(named: "GBK")))
        // Reproduce mojibake: GBK bytes read as Latin-1, then encoded as UTF-8.
        let garbledText = try #require(String(data: gbkBytes, encoding: .isoLatin1))
        let mojibakeData = Data(garbledText.utf8)
        try mojibakeData.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file, force: true)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-8-mojibake-latin1-gbk") == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("force re-convert repairs UTF-8 mojibake from GBK via cp1252")
    func forceReconvertRepairsMojibakeFromGBKViaCp1252() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mojibake-cp1252.txt")
        let sourceText = "简体中文内容测试，验证 cp1252 反推修复。"
        let gbkBytes = try #require(sourceText.data(using: encoding(named: "GBK")))
        let garbledText = try #require(String(data: gbkBytes, encoding: .windowsCP1252))
        let mojibakeData = Data(garbledText.utf8)
        try mojibakeData.write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file, force: true)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-8-mojibake-") == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("force re-convert bypasses cached utf-8 entry and repairs mojibake")
    func forceReconvertBypassesCachedUTF8Entry() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mojibake-cached.txt")
        let sourceText = "缓存记录为 utf-8 但实际是 mojibake，强制重转化应修复。"
        let gbkBytes = try #require(sourceText.data(using: encoding(named: "GBK")))
        let garbledText = try #require(String(data: gbkBytes, encoding: .isoLatin1))
        try Data(garbledText.utf8).write(to: file)

        let cache = TextEncodingConversionCache(storageURL: root.url.appendingPathComponent("cache.json"))
        let fingerprint = try file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        try cache.markUTF8(
            for: file,
            size: Int64(fingerprint.fileSize ?? 0),
            modifiedAt: fingerprint.contentModificationDate
        )

        // Non-force path returns alreadyUTF8 (cache hit).
        let nonForceResult = try TextEncodingConversionService(
            logger: CapturingLogger(),
            cache: cache
        ).convertFileToUTF8(file)
        #expect(nonForceResult.status == .alreadyUTF8)
        #expect(nonForceResult.usedCache == true)

        // Force path bypasses cache and repairs.
        let forceResult = try TextEncodingConversionService(
            logger: CapturingLogger(),
            cache: cache
        ).convertFileToUTF8(file, force: true)
        #expect(forceResult.status == .converted)
        #expect(forceResult.detectedEncoding?.hasPrefix("utf-8-mojibake-") == true)
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("non-force path leaves plain UTF-8 file untouched, force path keeps it as UTF-8")
    func forceReconvertKeepsPlainUTF8FileUntouched() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("plain-utf8.txt")
        let sourceText = "这是正常的 UTF-8 文件，无需修复。"
        try sourceText.write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file, force: true)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("pure GBK file is not mis-detected as cp1252 mojibake")
    func pureGBKFileNotMisDetectedAsCp1252() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("pure-gbk.txt")
        let sourceText = "简体中文内容测试，纯 GBK 编码文件不应被误判为 cp1252。"
        try #require(sourceText.data(using: encoding(named: "GBK"))).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "gbk")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("force re-convert repairs mojibake with sparse bad bytes via line-by-line fallback")
    func forceReconvertRepairsMojibakeWithSparseBadBytes() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mojibake-sparse.txt")
        // Two lines so detectMixedLineEncoding has multiple lines to work with.
        let line1 = "简体中文内容测试第一行，验证稀疏坏字节修复。"
        let line2 = "第二行继续中文内容，保证多行解码成功。"
        let sourceText = line1 + "\n" + line2
        var gbkBytes = try #require(sourceText.data(using: encoding(named: "GBK")))
        // Insert 0xAC at a byte boundary inside line 1: 0xAC is not a valid GBK lead byte,
        // so strict full-file GBK decode fails, but per-line decode succeeds for line 2.
        gbkBytes.insert(0xAC, at: 8)
        let garbledText = try #require(String(data: gbkBytes, encoding: .isoLatin1))
        try Data(garbledText.utf8).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file, force: true)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding?.hasPrefix("utf-8-mojibake-") == true)
        let repaired = try String(contentsOf: file, encoding: .utf8)
        #expect(repaired.contains("第二行继续中文内容"))
    }

    @Test("re-convert repairs embedded GB18030 mojibake without touching clean UTF-8 lines")
    func reconvertRepairsEmbeddedGB18030Mojibake() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("embedded-gb18030-mojibake.txt")
        let cleanLine = "这是正常的 UTF-8 行，应该保持不变。"
        let corruptedLine = "师傅笑着说：「你这砘铮\u{e0ef}谖艺馊\u{e42d}甑墓Ψ蛑\u{e1a6}拢\u{e0e9}蚁肟梢猿晌\u{e01c}捣\u{e48f}魏闻\u{e1a7}缘氖テ罚∧阋部梢越逵伤\u{e3cb}瘩补，但是记得，不要伤了人命！」"
        try (cleanLine + "\n" + corruptedLine + "\n" + cleanLine).write(
            to: file,
            atomically: true,
            encoding: .utf8
        )

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "utf-8-embedded-mojibake-gb18030-gb2312-lossy")
        let repaired = try String(contentsOf: file, encoding: .utf8)
        #expect(repaired.contains("在我这三年的功夫之下"))
        #expect(repaired.components(separatedBy: "\n").first == cleanLine)
        #expect(repaired.components(separatedBy: "\n").last == cleanLine)
        #expect(!repaired.contains("\u{e0ef}"))
    }

    @Test("force re-convert preserves intentional private-use UTF-8 glyphs")
    func forceReconvertPreservesIntentionalPrivateUseGlyphs() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("private-use-utf8.txt")
        let sourceText = "正常文本\n" + String(repeating: "\u{e4c6}", count: 20) + "\n后续文本"
        try sourceText.write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file, force: true)

        #expect(result.status == .alreadyUTF8)
        #expect(result.detectedEncoding == "utf-8")
        #expect(try String(contentsOf: file, encoding: .utf8) == sourceText)
    }

    @Test("force re-convert repairs mojibake runs next to replacement characters")
    func forceReconvertRepairsMojibakeRunsNextToReplacementCharacters() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("mojibake-with-replacements.txt")
        let corruptedLine = "\u{3000}\u{3000}男人淫笑着说：“臊拢\u{e0cc}鸱丫⒘耍\u{e0ef}僭趺囱\u{e294}\u{e0d9}退阆衷谖曳趴\u{e023}悖\u{e0e9}蚁旅婺嵌\u{e08b}骰共皇且丫\u{e13c}H进过你的吕锪耍\u{e0d5}佟\u{e11a}\u{e133}佟\u{e11a}\u{e11a}\u{fffd}"
        try ("正常 UTF-8 行\n" + corruptedLine + "\n正常 UTF-8 行")
            .write(to: file, atomically: true, encoding: .utf8)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file, force: true)

        #expect(result.status == .converted)
        #expect(result.detectedEncoding == "utf-8-embedded-mojibake-gb18030-gb2312-lossy")
        let repaired = try String(contentsOf: file, encoding: .utf8)
        #expect(!repaired.contains("\u{e0cc}"))
        #expect(repaired.contains("�"))
    }
}
