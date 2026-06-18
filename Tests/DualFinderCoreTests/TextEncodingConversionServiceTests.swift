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

    @Test("renames files when encoding cannot be identified")
    func renamesUnknownEncodingFiles() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("binary.dat")
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.detectedEncoding == nil)
        #expect(result.finalURL.lastPathComponent == "binary.dat_unknown_encode")
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: result.finalURL.path))
    }

    @Test("uses a unique unknown suffix destination")
    func usesUniqueUnknownSuffixDestination() throws {
        let root = try TemporaryDirectory()
        let file = root.url.appendingPathComponent("binary.dat")
        let existing = root.url.appendingPathComponent("binary.dat_unknown_encode")
        try Data([0xff, 0x00, 0xfe, 0x01]).write(to: file)
        try Data().write(to: existing)

        let result = try TextEncodingConversionService(logger: CapturingLogger()).convertFileToUTF8(file)

        #expect(result.status == .renamedUnknown)
        #expect(result.finalURL.lastPathComponent == "binary.dat_unknown_encode 2")
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

    private func encoding(named name: String) -> String.Encoding {
        let cfEncoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        let nsEncoding = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
        return String.Encoding(rawValue: nsEncoding)
    }
}
