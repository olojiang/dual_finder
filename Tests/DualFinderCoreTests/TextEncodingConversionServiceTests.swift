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

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
