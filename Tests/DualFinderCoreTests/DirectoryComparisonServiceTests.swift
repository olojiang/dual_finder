import Foundation
import Testing
@testable import DualFinderCore

@Suite("DirectoryComparisonService")
struct DirectoryComparisonServiceTests {
    @Test("compares recursive directory contents")
    func comparesRecursiveDirectoryContents() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        try "same".write(to: left.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
        try "same".write(to: right.appendingPathComponent("same.txt"), atomically: true, encoding: .utf8)
        let sameDate = Date()
        try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: left.appendingPathComponent("same.txt").path)
        try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: right.appendingPathComponent("same.txt").path)
        try "left".write(to: left.appendingPathComponent("left-only.txt"), atomically: true, encoding: .utf8)
        try "right".write(to: right.appendingPathComponent("right-only.txt"), atomically: true, encoding: .utf8)
        try "one".write(to: left.appendingPathComponent("changed.txt"), atomically: true, encoding: .utf8)
        Thread.sleep(forTimeInterval: 0.01)
        try "two".write(to: right.appendingPathComponent("changed.txt"), atomically: true, encoding: .utf8)

        let entries = try DirectoryComparisonService().compare(left: left, right: right)
        let statuses = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.status) })

        #expect(statuses["left-only.txt"] == .onlyLeft)
        #expect(statuses["right-only.txt"] == .onlyRight)
        #expect(statuses["changed.txt"] == .different)
        #expect(statuses["same.txt"] == .same)
    }

    @Test("compares files inside nested subdirectories by relative path")
    func comparesNestedSubdirectoryContents() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        let leftNested = left.appendingPathComponent("sub", isDirectory: true)
        let rightNested = right.appendingPathComponent("sub", isDirectory: true)
        try FileManager.default.createDirectory(at: leftNested, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rightNested, withIntermediateDirectories: true)

        let sameDate = Date()
        try "nested-same".write(to: leftNested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
        try "nested-same".write(to: rightNested.appendingPathComponent("deep.txt"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: leftNested.appendingPathComponent("deep.txt").path)
        try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: rightNested.appendingPathComponent("deep.txt").path)
        try "left-deep".write(to: leftNested.appendingPathComponent("left-only.txt"), atomically: true, encoding: .utf8)

        let entries = try DirectoryComparisonService().compare(left: left, right: right)
        let statuses = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.status) })

        #expect(statuses["sub/deep.txt"] == .same)
        #expect(statuses["sub/left-only.txt"] == .onlyLeft)
    }

    @Test("excludes hidden files by default and includes them when requested")
    func hiddenFilesRespectIncludeHiddenFlag() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)

        let sameDate = Date()
        try "hidden".write(to: left.appendingPathComponent(".secret"), atomically: true, encoding: .utf8)
        try "hidden".write(to: right.appendingPathComponent(".secret"), atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: left.appendingPathComponent(".secret").path)
        try FileManager.default.setAttributes([.modificationDate: sameDate], ofItemAtPath: right.appendingPathComponent(".secret").path)

        let defaultEntries = try DirectoryComparisonService().compare(left: left, right: right)
        let defaultPaths = Set(defaultEntries.map(\.relativePath))
        #expect(!defaultPaths.contains(".secret"))

        let includingHidden = try DirectoryComparisonService().compare(left: left, right: right, includeHidden: true)
        let hiddenStatuses = Dictionary(uniqueKeysWithValues: includingHidden.map { ($0.relativePath, $0.status) })
        #expect(hiddenStatuses[".secret"] == .same)
    }

    @Test("enumerates symlinks as comparable entries")
    func enumeratesSymlinksAsEntries() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)

        let target = root.url.appendingPathComponent("target.txt")
        try "payload".write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: left.appendingPathComponent("link.txt"),
            withDestinationURL: target
        )

        let entries = try DirectoryComparisonService().compare(left: left, right: right)
        let statuses = Dictionary(uniqueKeysWithValues: entries.map { ($0.relativePath, $0.status) })

        #expect(statuses["link.txt"] == .onlyLeft)
    }

    @Test("throws cancelled when cancellation token is set before comparison")
    func throwsCancelledWhenPreCancelled() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        try "a".write(to: left.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)

        let cancellation = FileOperationCancellation()
        cancellation.cancel()

        #expect(throws: FileOperationError.cancelled) {
            try DirectoryComparisonService().compare(
                left: left,
                right: right,
                cancellation: cancellation
            )
        }
    }

    @Test("reports progress with cumulative scanned item count")
    func reportsProgressWithCumulativeScannedCount() throws {
        let root = try TemporaryDirectory()
        let left = root.url.appendingPathComponent("left", isDirectory: true)
        let right = root.url.appendingPathComponent("right", isDirectory: true)
        try FileManager.default.createDirectory(at: left, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: right, withIntermediateDirectories: true)
        for index in 0..<150 {
            try "body-\(index)".write(to: left.appendingPathComponent("left-\(index).txt"), atomically: true, encoding: .utf8)
            try "body-\(index)".write(to: right.appendingPathComponent("right-\(index).txt"), atomically: true, encoding: .utf8)
        }

        var reportedCounts: [Int] = []
        let entries = try DirectoryComparisonService().compare(
            left: left,
            right: right,
            progress: { reportedCounts.append($0) }
        )

        #expect(!entries.isEmpty)
        #expect(reportedCounts.contains(100))
        // Final report covers left (150 files) + right (150 files) = 300.
        #expect(reportedCounts.last == 300)
    }
}
