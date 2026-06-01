import Foundation

public enum ContextMenuSelection {
    public static let minimumSelectionCountForNewFolder = 2

    public static func orderedDirectories(in selection: Set<URL>, items: [FileItem]) -> [URL] {
        items
            .filter { selection.contains($0.url) && $0.isDirectoryLike }
            .map(\.url)
    }

    public static func allSelectedAreDirectories(selection: Set<URL>, items: [FileItem]) -> Bool {
        guard !selection.isEmpty else { return false }
        let directories = orderedDirectories(in: selection, items: items)
        return directories.count == selection.count
    }

    public static func canCreateFolderWithSelection(_ selection: Set<URL>) -> Bool {
        selection.count >= minimumSelectionCountForNewFolder
    }

    public static func moveSources(
        _ sources: [URL],
        into folder: URL,
        fileManager: FileManager = .default
    ) -> [URL] {
        let folderURL = folder.standardizedFileURL
        let folderPath = folderURL.path
        return sources.filter { source in
            let sourceURL = source.standardizedFileURL
            if sourceURL == folderURL {
                return false
            }
            let sourcePath = sourceURL.path
            if folderPath.hasPrefix(sourcePath + "/") {
                return false
            }
            return true
        }
    }

    public static func isEmptyDirectory(at url: URL, fileManager: FileManager = .default) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return false
        }
        return (try? fileManager.contentsOfDirectory(atPath: url.path))?.isEmpty == true
    }
}
