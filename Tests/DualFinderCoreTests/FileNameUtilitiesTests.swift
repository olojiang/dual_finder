import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileNameUtilities")
struct FileNameUtilitiesTests {
    @Test("detects blank and invalid path component names")
    func detectsBlankAndInvalidNames() {
        #expect(FileNameUtilities.isBlank(" \n\t "))
        #expect(!FileNameUtilities.isBlank("report"))
        #expect(FileNameUtilities.containsInvalidPathComponentCharacters("bad/name"))
        #expect(FileNameUtilities.containsInvalidPathComponentCharacters("bad:name"))
        #expect(!FileNameUtilities.containsInvalidPathComponentCharacters("good name.txt"))
    }

    @Test("normalizes extension text for rename rules")
    func normalizesExtensionText() {
        #expect(FileNameUtilities.normalizedExtension(".txt ") == "txt")
        #expect(FileNameUtilities.normalizedExtension(" .tar.gz ") == "tar.gz")
        #expect(FileNameUtilities.normalizedExtension("   ") == "")
    }

    @Test("builds numbered copy names while preserving extensions")
    func buildsNumberedCopyNames() {
        #expect(FileNameUtilities.numberedCopyName(for: "Report.txt", index: 2) == "Report 2.txt")
        #expect(FileNameUtilities.numberedCopyName(for: "Folder", index: 3) == "Folder 3")
        #expect(FileNameUtilities.extensionWithDot(for: "archive.tar.gz") == ".gz")
        #expect(FileNameUtilities.extensionWithDot(for: "README") == "")
    }
}
