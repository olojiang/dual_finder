import Foundation
import Testing
@testable import DualFinderCore

@Suite("ContextMenuSelection")
struct ContextMenuSelectionTests {
    @Test("detects when every selected item is a directory")
    func allSelectedAreDirectories() {
        let folder = fileItem(name: "Projects", kind: .folder)
        let file = fileItem(name: "readme.txt", kind: .file)
        let selection: Set<URL> = [folder.url, file.url]

        #expect(ContextMenuSelection.allSelectedAreDirectories(selection: selection, items: [folder, file]) == false)
        #expect(ContextMenuSelection.allSelectedAreDirectories(selection: [folder.url], items: [folder, file]) == true)
    }

    @Test("requires at least two items for new folder with selection")
    func newFolderSelectionThreshold() {
        let url = URL(fileURLWithPath: "/tmp/a")

        #expect(ContextMenuSelection.canCreateFolderWithSelection([]) == false)
        #expect(ContextMenuSelection.canCreateFolderWithSelection([url]) == false)
        #expect(
            ContextMenuSelection.canCreateFolderWithSelection([
                url,
                URL(fileURLWithPath: "/tmp/b")
            ]) == true
        )
    }

    @Test("filters move sources that would nest the destination inside a source")
    func moveSourcesExcludesInvalidTargets() {
        let parent = URL(fileURLWithPath: "/tmp/parent")
        let child = parent.appendingPathComponent("child")
        let folder = parent.appendingPathComponent("new folder")

        let filtered = ContextMenuSelection.moveSources(
            [parent, child, folder],
            into: folder
        )

        #expect(filtered == [child])
    }

    @Test("detects empty directories")
    func isEmptyDirectory() throws {
        let root = try TemporaryDirectory()

        let folder = root.url.appendingPathComponent("empty")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        #expect(ContextMenuSelection.isEmptyDirectory(at: folder) == true)

        let file = folder.appendingPathComponent("a.txt")
        try Data().write(to: file)

        #expect(ContextMenuSelection.isEmptyDirectory(at: folder) == false)
    }

    private func fileItem(name: String, kind: FileItemKind) -> FileItem {
        let url = URL(fileURLWithPath: "/tmp/\(name)")
        return FileItem(
            url: url,
            name: name,
            kind: kind,
            type: kind.rawValue,
            size: nil,
            modifiedAt: nil,
            isHidden: false
        )
    }
}
