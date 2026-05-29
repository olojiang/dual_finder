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
}
