import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileOperationVolume")
struct FileOperationVolumeTests {
    @Test("same directory paths share device identifier")
    func sameDirectorySharesDevice() throws {
        let root = try TemporaryDirectory()
        let nested = root.url.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(FileOperationVolume.isOnSameDevice(root.url, as: nested))
        #expect(FileOperationVolume.canRenameMove(sources: [nested], to: root.url))
    }

    @Test("device identifier is stable for a path")
    func deviceIdentifierIsStable() throws {
        let root = try TemporaryDirectory()
        let child = root.url.appendingPathComponent("child.txt")
        try "x".write(to: child, atomically: true, encoding: .utf8)
        let first = FileOperationVolume.deviceIdentifier(root.url)
        let second = FileOperationVolume.deviceIdentifier(child)
        #expect(first != nil)
        #expect(first == second)
    }
}
