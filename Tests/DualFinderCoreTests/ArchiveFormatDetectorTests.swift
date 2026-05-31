import Foundation
import Testing
@testable import DualFinderCore

@Suite("ArchiveFormatDetector")
struct ArchiveFormatDetectorTests {
    @Test("detects common archive extensions")
    func detectsExtensions() {
        #expect(ArchiveFormatDetector.format(for: url("backup.zip")) == .zip)
        #expect(ArchiveFormatDetector.format(for: url("data.tar")) == .tar)
        #expect(ArchiveFormatDetector.format(for: url("bundle.tar.gz")) == .tarGzip)
        #expect(ArchiveFormatDetector.format(for: url("bundle.tgz")) == .tarGzip)
        #expect(ArchiveFormatDetector.format(for: url("bundle.tar.bz2")) == .tarBzip2)
        #expect(ArchiveFormatDetector.format(for: url("bundle.tbz2")) == .tarBzip2)
        #expect(ArchiveFormatDetector.format(for: url("bundle.tar.xz")) == .tarXz)
        #expect(ArchiveFormatDetector.format(for: url("bundle.txz")) == .tarXz)
        #expect(ArchiveFormatDetector.format(for: url("image.iso")) == .iso)
        #expect(ArchiveFormatDetector.format(for: url("archive.7z")) == .sevenZip)
        #expect(ArchiveFormatDetector.format(for: url("archive.rar")) == .rar)
    }

    @Test("does not treat tar.gz as plain gzip")
    func tarGzipNotGzip() {
        #expect(ArchiveFormatDetector.format(for: url("foo.tar.gz")) == .tarGzip)
        #expect(ArchiveFormatDetector.format(for: url("foo.gz")) == .gzip)
    }

    @Test("extraction folder name strips compound suffixes")
    func extractionFolderName() {
        #expect(ArchiveFormatDetector.extractionFolderName(for: url("project.tar.gz")) == "project")
        #expect(ArchiveFormatDetector.extractionFolderName(for: url("project.tgz")) == "project")
        #expect(ArchiveFormatDetector.extractionFolderName(for: url("backup.zip")) == "backup")
        #expect(ArchiveFormatDetector.extractionFolderName(for: url("data.tar")) == "data")
    }

    @Test("non-archive returns nil")
    func nonArchive() {
        #expect(ArchiveFormatDetector.format(for: url("readme.txt")) == nil)
        #expect(ArchiveFormatDetector.isExtractable(url("folder")) == false)
    }

    private func url(_ name: String) -> URL {
        URL(fileURLWithPath: "/tmp/\(name)")
    }
}
