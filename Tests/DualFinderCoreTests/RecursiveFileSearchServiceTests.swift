import Foundation
import Testing
@testable import DualFinderCore

@Suite("RecursiveFileSearchService")
struct RecursiveFileSearchServiceTests {
    @Test("searches names and optional file contents recursively")
    func searchesNamesAndContentsRecursively() throws {
        let root = try TemporaryDirectory()
        let nested = root.url.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let nameMatch = nested.appendingPathComponent("invoice.txt")
        let contentMatch = nested.appendingPathComponent("notes.md")
        try "ordinary text".write(to: nameMatch, atomically: true, encoding: .utf8)
        try "needle appears here".write(to: contentMatch, atomically: true, encoding: .utf8)

        let nameResults = try RecursiveFileSearchService().search(root: root.url, query: "invoice")
        let contentResults = try RecursiveFileSearchService().search(
            root: root.url,
            query: "needle",
            options: RecursiveFileSearchOptions(searchContents: true)
        )

        #expect(nameResults.map(\.url).contains(nameMatch.standardizedFileURL))
        #expect(contentResults.contains { $0.url == contentMatch.standardizedFileURL && $0.matchedContent })
    }

    @Test("skips package descendants during recursive search")
    func skipsPackageDescendants() throws {
        let root = try TemporaryDirectory()
        let package = root.url.appendingPathComponent("Demo.app", isDirectory: true)
        let packageContents = package.appendingPathComponent("Contents", isDirectory: true)
        let internalFile = packageContents.appendingPathComponent("needle.txt")
        try FileManager.default.createDirectory(at: packageContents, withIntermediateDirectories: true)
        try "needle appears here".write(to: internalFile, atomically: true, encoding: .utf8)

        let results = try RecursiveFileSearchService().search(
            root: root.url,
            query: "needle",
            options: RecursiveFileSearchOptions(searchContents: true)
        )

        #expect(results.isEmpty)
    }

    @Test("matches package directory itself during recursive search")
    func matchesPackageDirectoryItself() throws {
        let root = try TemporaryDirectory()
        let package = root.url.appendingPathComponent("Demo.app", isDirectory: true)
        let packageContents = package.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: packageContents, withIntermediateDirectories: true)

        let results = try RecursiveFileSearchService().search(root: root.url, query: "Demo")

        #expect(results.map(\.url) == [package.standardizedFileURL])
    }
}
