import AppKit
import Foundation
import SwiftUI
import DualFinderCore

struct PathEditRequest: Equatable {
    let id = UUID()
    let side: PaneSide
}

struct PaneFocusRequest: Equatable {
    let id = UUID()
    let requestID: String
    let side: PaneSide
    let source: String
    let revealURL: URL?
}

struct FileSearchRequest: Equatable {
    let id = UUID()
    let side: PaneSide
}

struct FolderBookmarkDialogRequest: Identifiable, Equatable {
    let id = UUID()
}

struct BatchRenameDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
}

enum FileClipboardOperation: String {
    case copy
    case move
}

@MainActor
final class DualFinderViewModel: ObservableObject {
    @Published var leftPane: PaneState
    @Published var rightPane: PaneState
    @Published private(set) var leftItems: [FileItem] = []
    @Published private(set) var rightItems: [FileItem] = []
    @Published var statusMessage: String = ""
    @Published var diskAccessPrompt: DiskAccessPrompt?
    @Published private(set) var activePaneSide: PaneSide = .left
    @Published var pathEditRequest: PathEditRequest?
    @Published var paneFocusRequest: PaneFocusRequest?
    @Published var fileSearchRequest: FileSearchRequest?
    @Published var folderBookmarkDialogRequest: FolderBookmarkDialogRequest?
    @Published var batchRenameDialogRequest: BatchRenameDialogRequest?
    @Published private(set) var fileOperationQueue: [QueuedFileOperation] = []
    @Published var fileConflictDialogRequest: FileConflictDialogRequest?
    @Published var directoryComparisonDialogRequest: DirectoryComparisonDialogRequest?
    @Published var globalSearchDialogRequest: GlobalSearchDialogRequest?
    @Published private(set) var directoryComparisonResults: [DirectoryComparisonEntry] = []
    @Published private(set) var globalSearchResults: [RecursiveFileSearchResult] = []
    @Published private(set) var isGlobalSearchRunning = false
    @Published var isInlineRenaming = false
    @Published private(set) var folderBookmarkRevision = 0
    @Published var showHiddenFiles = false {
        didSet { refreshAll() }
    }

    private let fileSystem: FileSystemService
    private let operationService: FileOperationService
    private let sortRuleStore: FolderSortRuleStore
    private let paneSessionStore: PaneSessionStore
    private let folderBookmarkStore: FolderBookmarkStore
    private let folderSizeCache: FolderSizeCache
    private let permissionGuide: PrivacyPermissionGuide
    private let quickLookPreviewService: QuickLookPreviewService
    private let logger: AppLogging
    private var didAutoOpenDiskAccessSettings = false
    private var pendingOperationRequests: [QueuedFileOperationRequest] = []
    private var isProcessingFileOperations = false
    private var activeConflictAnswerBox: FileConflictAnswerBox?
    private var globalSearchCancellation: FileOperationCancellation?
    private var archiveCancellation: FileOperationCancellation?
    private var isArchiveOperationRunning = false

    init(
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: FileSystemService = FileSystemService(),
        sortRuleStore: FolderSortRuleStore = FolderSortRuleStore(),
        paneSessionStore: PaneSessionStore = PaneSessionStore(),
        folderBookmarkStore: FolderBookmarkStore = FolderBookmarkStore(),
        folderSizeCache: FolderSizeCache = FolderSizeCache(),
        permissionGuide: PrivacyPermissionGuide = PrivacyPermissionGuide(),
        quickLookPreviewService: QuickLookPreviewService = QuickLookPreviewService(),
        logger: AppLogging
    ) {
        self.fileSystem = fileSystem
        self.sortRuleStore = sortRuleStore
        self.paneSessionStore = paneSessionStore
        self.folderBookmarkStore = folderBookmarkStore
        self.folderSizeCache = folderSizeCache
        self.permissionGuide = permissionGuide
        self.quickLookPreviewService = quickLookPreviewService
        self.logger = logger
        let restoredPanes = paneSessionStore.load(fallbackURL: initialURL)
        leftPane = restoredPanes.left
        rightPane = restoredPanes.right
        operationService = FileOperationService(logger: logger)
        self.quickLookPreviewService.navigationHandler = { [weak self] direction in
            self?.previewAdjacentSelection(direction) ?? false
        }
        logger.info("view-model", "initialized", metadata: [
            "initialURL": initialURL.path,
            "leftURL": leftPane.selectedURL.path,
            "rightURL": rightPane.selectedURL.path
        ])
    }

    func items(for side: PaneSide) -> [FileItem] {
        side == .left ? leftItems : rightItems
    }

    func pane(for side: PaneSide) -> PaneState {
        side == .left ? leftPane : rightPane
    }

    func sortRule(for side: PaneSide) -> FileSortRule {
        sortRuleStore.rule(for: pane(for: side).selectedURL)
    }

    var hasActiveSelection: Bool {
        hasSelection(on: activePaneSide)
    }

    func hasSelection(on side: PaneSide) -> Bool {
        !pane(for: side).selectedItemURLs.isEmpty
    }

    func bindingForSelection(side: PaneSide) -> Binding<Set<URL>> {
        Binding(
            get: { self.pane(for: side).selectedItemURLs },
            set: { newValue in
                self.activatePane(side)
                guard self.pane(for: side).selectedItemURLs != newValue else { return }

                self.setSelection(newValue, for: side)
                self.logger.debug("selection", "selection.changed", metadata: [
                    "side": side.rawValue,
                    "count": "\(newValue.count)"
                ])
            }
        )
    }

    func activatePane(_ side: PaneSide) {
        activePaneSide = side
    }

    func requestPaneFocus(_ side: PaneSide, requestID: String, source: String) {
        let previousSide = activePaneSide
        logger.debug("pane-focus", "switch.requested", metadata: [
            "requestID": requestID,
            "from": previousSide.rawValue,
            "to": side.rawValue,
            "source": source
        ])

        activePaneSide = side
        let revealURL = selectionRevealURLForPaneFocus(side, requestID: requestID, source: source)
        paneFocusRequest = PaneFocusRequest(requestID: requestID, side: side, source: source, revealURL: revealURL)

        logger.info("pane-focus", "switch.applied", metadata: [
            "requestID": requestID,
            "from": previousSide.rawValue,
            "to": side.rawValue,
            "source": source,
            "changed": "\(previousSide != side)",
            "revealPath": revealURL?.path ?? ""
        ])
    }

    private func selectionRevealURLForPaneFocus(_ side: PaneSide, requestID: String, source: String) -> URL? {
        let itemURLs = items(for: side).map(\.url)
        let selection = pane(for: side).selectedItemURLs

        if let selectedURL = itemURLs.first(where: { selection.contains($0) }) {
            return selectedURL
        }

        guard let firstURL = itemURLs.first else {
            logger.debug("selection", "focus-default.ignored", metadata: [
                "requestID": requestID,
                "side": side.rawValue,
                "source": source,
                "reason": "empty-directory"
            ])
            return nil
        }

        setSelection([firstURL], for: side)
        logger.debug("selection", "focus-default.selected", metadata: [
            "requestID": requestID,
            "side": side.rawValue,
            "source": source,
            "path": firstURL.path
        ])
        return firstURL
    }

    func logPaneFocusEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("pane-focus", message, metadata: metadata)
    }

    func logShortcutEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("shortcut", message, metadata: metadata)
    }

    func requestPathEditing(on side: PaneSide) {
        activatePane(side)
        pathEditRequest = PathEditRequest(side: side)
    }

    func requestFileSearch(on side: PaneSide) {
        guard !isInlineRenaming else { return }
        activatePane(side)
        fileSearchRequest = FileSearchRequest(side: side)
        logger.debug("file-search", "requested", metadata: [
            "side": side.rawValue,
            "path": pane(for: side).selectedURL.path
        ])
    }

    func requestFolderBookmarkDialog(on side: PaneSide) {
        guard !isInlineRenaming else { return }
        activatePane(side)
        folderBookmarkDialogRequest = FolderBookmarkDialogRequest()
    }

    func requestBatchRenameDialog(on side: PaneSide) {
        guard !isInlineRenaming else { return }
        let selectedItems = selectedItems(on: side)
        guard !selectedItems.isEmpty else {
            statusMessage = "Select files or folders to rename"
            return
        }

        activatePane(side)
        batchRenameDialogRequest = BatchRenameDialogRequest(side: side)
        logger.info("batch-rename", "dialog.requested", metadata: [
            "side": side.rawValue,
            "count": "\(selectedItems.count)"
        ])
    }

    func requestDirectoryComparison() {
        guard !isInlineRenaming else { return }
        directoryComparisonDialogRequest = DirectoryComparisonDialogRequest()
        compareDirectories()
    }

    func requestGlobalSearchDialog() {
        guard !isInlineRenaming else { return }
        globalSearchDialogRequest = GlobalSearchDialogRequest()
        globalSearchResults = []
    }

    func folderBookmarkEntries() -> [FolderBookmarkEntry] {
        folderBookmarkStore.entries()
    }

    func logFolderBookmarkDialogEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("folder-bookmark-dialog", message, metadata: metadata)
    }

    func logFileSearchEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("file-search", message, metadata: metadata)
    }

    func logDragDropEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("drag-drop", message, metadata: metadata)
    }

    func isFolderFavorite(_ url: URL) -> Bool {
        folderBookmarkStore.isFavorite(url)
    }

    func selectedDirectoryURLs(in selection: Set<URL>, on side: PaneSide) -> [URL] {
        ContextMenuSelection.orderedDirectories(in: selection, items: items(for: side))
    }

    func allSelectedItemsAreDirectories(in selection: Set<URL>, on side: PaneSide) -> Bool {
        ContextMenuSelection.allSelectedAreDirectories(selection: selection, items: items(for: side))
    }

    func canCreateFolderWithSelection(_ selection: Set<URL>) -> Bool {
        ContextMenuSelection.canCreateFolderWithSelection(selection)
    }

    func shareItems(_ urls: [URL], on side: PaneSide) {
        activatePane(side)
        let ordered = urls.isEmpty ? orderedSelection(pane(for: side).selectedItemURLs, on: side) : urls
        guard !ordered.isEmpty else { return }

        SharingServicePresenter.presentSharePicker(for: ordered)
        statusMessage = ordered.count == 1
            ? "Share: \(ordered[0].lastPathComponent)"
            : "Share \(ordered.count) items"
        logger.info("share", "picker.presented", metadata: [
            "side": side.rawValue,
            "count": "\(ordered.count)"
        ])
    }

    func openSelectionInNewTabs(on side: PaneSide, folderURLs: [URL]) {
        let directories = folderURLs.isEmpty
            ? selectedDirectoryURLs(in: pane(for: side).selectedItemURLs, on: side)
            : folderURLs
        guard !directories.isEmpty else { return }

        activatePane(side)
        for url in directories {
            _ = mutatePane(side) { pane in
                pane.addTab(url: url)
            }
        }
        persistPaneSession()
        refresh(side)
        statusMessage = directories.count == 1
            ? "Opened tab: \(directories[0].lastPathComponent)"
            : "Opened \(directories.count) tabs"
        logger.info("tab", "tabs.opened.from-selection", metadata: [
            "side": side.rawValue,
            "count": "\(directories.count)"
        ])
    }

    func moveItems(_ sources: [URL], into folder: URL, on side: PaneSide) {
        let moveSources = ContextMenuSelection.moveSources(sources, into: folder)
        guard !moveSources.isEmpty else { return }

        activatePane(side)
        setSelection([folder], for: side)
        enqueueFileOperation(.move, sources: moveSources, destination: folder)
        logger.info("file-operation", "move.into-folder.requested", metadata: [
            "side": side.rawValue,
            "folder": folder.path,
            "count": "\(moveSources.count)"
        ])
    }

    @discardableResult
    func commitNewFolderWithSelection(
        folder createdFolder: URL,
        newName: String,
        movingSources sources: [URL],
        on side: PaneSide
    ) -> Bool {
        do {
            let renamedFolder = try operationService.rename(createdFolder, to: newName)
            refresh(side)
            moveItems(sources, into: renamedFolder, on: side)
            return true
        } catch {
            reportOperationFailure("new-folder-with-selection.failed", error: error)
            return false
        }
    }

    func cancelNewFolderWithSelection(
        folder createdFolder: URL,
        restoringSelection sources: [URL],
        on side: PaneSide
    ) {
        if ContextMenuSelection.isEmptyDirectory(at: createdFolder) {
            try? FileManager.default.removeItem(at: createdFolder)
            refresh(side)
            logger.info("file-operation", "new-folder-with-selection.cancelled", metadata: [
                "side": side.rawValue,
                "path": createdFolder.path
            ])
        }
        setSelection(Set(sources), for: side)
        statusMessage = "Cancelled new folder"
    }

    func addFolderToFavorites(_ url: URL) {
        folderBookmarkStore.addFavorite(url)
        folderBookmarkRevision += 1
        statusMessage = "Added favorite: \(url.path)"
        logger.info("folder-bookmark", "favorite.added", metadata: [
            "path": url.path
        ])
    }

    func addActiveFolderToFavorites() {
        addFolderToFavorites(pane(for: activePaneSide).selectedURL)
    }

    func removeFolderFavorite(_ url: URL) {
        folderBookmarkStore.removeFavorite(url)
        folderBookmarkRevision += 1
        statusMessage = "Removed favorite: \(url.path)"
        logger.info("folder-bookmark", "favorite.removed", metadata: [
            "path": url.path
        ])
    }

    func navigateToBookmarkedFolder(_ url: URL) {
        navigate(activePaneSide, to: url)
    }

    func selectItem(_ url: URL, on side: PaneSide) {
        activatePane(side)
        guard pane(for: side).selectedItemURLs != [url] else { return }

        setSelection([url], for: side)
        logger.debug("selection", "item.selected", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
    }

    func toggleItemSelection(_ url: URL, on side: PaneSide) {
        activatePane(side)

        var selection = pane(for: side).selectedItemURLs
        if selection.contains(url) {
            selection.remove(url)
        } else {
            selection.insert(url)
        }

        setSelection(selection, for: side)
        logger.debug("selection", "item.toggled", metadata: [
            "side": side.rawValue,
            "count": "\(selection.count)",
            "path": url.path
        ])
    }

    func replaceSelection(_ selection: Set<URL>, on side: PaneSide, source: String) {
        activatePane(side)
        guard pane(for: side).selectedItemURLs != selection else { return }

        setSelection(selection, for: side)
        logger.debug("selection", "selection.replaced", metadata: [
            "side": side.rawValue,
            "count": "\(selection.count)",
            "source": source
        ])
    }

    func extendSelection(to url: URL, on side: PaneSide) {
        activatePane(side)

        let itemURLs = items(for: side).map(\.url)
        guard let targetIndex = itemURLs.firstIndex(of: url) else {
            selectItem(url, on: side)
            return
        }

        let selectedIndexes = pane(for: side).selectedItemURLs.compactMap { itemURLs.firstIndex(of: $0) }
        let anchorIndex = selectedIndexes.min() ?? targetIndex
        let bounds = min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)
        let selection = Set(itemURLs[bounds])

        guard pane(for: side).selectedItemURLs != selection else { return }
        setSelection(selection, for: side)
        logger.debug("selection", "range.extended", metadata: [
            "side": side.rawValue,
            "count": "\(selection.count)",
            "path": url.path
        ])
    }

    func activateItem(_ url: URL, on side: PaneSide) {
        activatePane(side)
        setSelection([url], for: side)
        navigate(side, to: url)
    }

    func activateFirstItem(in selection: Set<URL>, on side: PaneSide) {
        guard let url = items(for: side).first(where: { selection.contains($0.url) })?.url ?? selection.first else {
            return
        }
        activateItem(url, on: side)
    }

    func refreshAll() {
        refresh(.left)
        refresh(.right)
    }

    func checkFullDiskAccessOnLaunch() {
        guard let error = permissionGuide.fullDiskAccessProbeFailure() else { return }

        statusMessage = "Full Disk Access is required for protected folders."
        handlePossiblePermissionFailure(error, path: "Full Disk Access probe")
    }

    func refresh(_ side: PaneSide) {
        let currentURL = pane(for: side).selectedURL
        do {
            let rule = sortRuleStore.rule(for: currentURL)
            let nextItems = try fileSystem.contents(
                of: currentURL,
                includeHidden: showHiddenFiles,
                sortRule: rule,
                folderSizeCache: folderSizeCache
            )
            setItems(nextItems, for: side)
            statusMessage = "\(currentURL.path) - \(nextItems.count) items"
            logger.info("navigation", "directory.refreshed", metadata: [
                "side": side.rawValue,
                "path": currentURL.path,
                "count": "\(nextItems.count)",
                "showHidden": "\(showHiddenFiles)",
                "sort": "\(rule.field.rawValue).\(rule.direction.rawValue)"
            ])
        } catch {
            statusMessage = "Failed to read \(currentURL.path): \(error.localizedDescription)"
            logger.error("navigation", "directory.refresh.failed", metadata: [
                "side": side.rawValue,
                "path": currentURL.path,
                "error": error.localizedDescription
            ])
            handlePossiblePermissionFailure(error, path: currentURL.path)
        }
    }

    func selectSortField(_ field: FileSortField, for side: PaneSide) {
        let folder = pane(for: side).selectedURL
        let nextRule = sortRuleStore.rule(for: folder).selecting(field)
        sortRuleStore.setRule(nextRule, for: folder)
        logger.info("sorting", "sort.changed", metadata: [
            "side": side.rawValue,
            "path": folder.path,
            "sort": "\(nextRule.field.rawValue).\(nextRule.direction.rawValue)"
        ])
        refresh(side)
    }

    func navigate(_ side: PaneSide, to url: URL, selecting selection: URL? = nil) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            openInFinder(url)
            return
        }
        mutatePane(side) { $0.navigateSelectedTab(to: url, selecting: selection) }
        folderBookmarkStore.recordRecentFolder(url)
        persistPaneSession()
        logger.info("navigation", "directory.changed", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
        refresh(side)
    }

    func navigateBack(_ side: PaneSide) {
        guard !isInlineRenaming else { return }
        guard let url = mutatePane(side, { $0.navigateSelectedTabBack() }) else {
            logger.debug("navigation", "history.back.ignored", metadata: ["side": side.rawValue])
            return
        }

        folderBookmarkStore.recordRecentFolder(url)
        persistPaneSession()
        logger.info("navigation", "history.back", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
        refresh(side)
    }

    func navigateForward(_ side: PaneSide) {
        guard !isInlineRenaming else { return }
        guard let url = mutatePane(side, { $0.navigateSelectedTabForward() }) else {
            logger.debug("navigation", "history.forward.ignored", metadata: ["side": side.rawValue])
            return
        }

        folderBookmarkStore.recordRecentFolder(url)
        persistPaneSession()
        logger.info("navigation", "history.forward", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
        refresh(side)
    }

    @discardableResult
    func navigateToFolderPath(_ pathText: String, on side: PaneSide) -> Bool {
        let trimmedPath = pathText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty else {
            statusMessage = "Enter a folder path"
            return false
        }

        let url = folderURL(fromPathText: trimmedPath, relativeTo: pane(for: side).selectedURL)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            statusMessage = "Folder not found: \(url.path)"
            logger.warning("navigation", "path.entry.missing", metadata: [
                "side": side.rawValue,
                "path": url.path
            ])
            return false
        }

        guard isDirectory.boolValue else {
            statusMessage = "Not a folder: \(url.path)"
            logger.warning("navigation", "path.entry.not-folder", metadata: [
                "side": side.rawValue,
                "path": url.path
            ])
            return false
        }

        navigate(side, to: url)
        return true
    }

    func navigateUp(_ side: PaneSide) {
        let currentURL = pane(for: side).selectedURL
        guard let parent = fileSystem.parent(of: currentURL) else { return }
        navigate(side, to: parent, selecting: currentURL)
    }

    func navigateIntoSelectedDirectory(_ side: PaneSide) {
        let selected = pane(for: side).selectedItemURLs
        guard let directory = items(for: side).first(where: { selected.contains($0.url) && $0.isDirectoryLike }) else {
            return
        }
        navigate(side, to: directory.url)
    }

    func openSelectionWithDefaultApp(on side: PaneSide) {
        let selected = pane(for: side).selectedItemURLs
        let urls = items(for: side).filter { selected.contains($0.url) }.map(\.url)
        guard !urls.isEmpty else { return }

        for url in urls {
            logger.info("file-open", "item.opened.default-app", metadata: [
                "side": side.rawValue,
                "path": url.path
            ])
            NSWorkspace.shared.open(url)
        }
        statusMessage = "Opened \(urls.count) item(s)"
    }

    func copyAbsolutePaths(_ urls: Set<URL>, on side: PaneSide) {
        let orderedURLs = orderedSelection(urls, on: side)
        guard !orderedURLs.isEmpty else { return }

        let paths = orderedURLs.map { $0.standardizedFileURL.path }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        statusMessage = paths.count == 1 ? "Copied path: \(paths[0])" : "Copied \(paths.count) paths"
        logger.info("clipboard", "absolute-paths.copied", metadata: [
            "side": side.rawValue,
            "count": "\(paths.count)"
        ])
    }

    func copySelectionToFileClipboard(on side: PaneSide, requestID: String? = nil) {
        guard !isInlineRenaming else {
            logger.debug("clipboard", "files.copy.ignored", metadata: metadataWithRequestID([
                "side": side.rawValue,
                "reason": "inline-renaming"
            ], requestID: requestID))
            return
        }

        let urls = orderedSelection(pane(for: side).selectedItemURLs, on: side)
        guard !urls.isEmpty else {
            logger.debug("clipboard", "files.copy.ignored", metadata: metadataWithRequestID([
                "side": side.rawValue,
                "reason": "empty-selection"
            ], requestID: requestID))
            return
        }

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let didWrite = pasteboard.writeObjects(urls.map { $0 as NSURL })
        guard didWrite else {
            logger.error("clipboard", "files.copy.failed", metadata: metadataWithRequestID([
                "side": side.rawValue,
                "count": "\(urls.count)"
            ], requestID: requestID))
            statusMessage = "Failed to copy \(urls.count) item(s)"
            return
        }

        statusMessage = "Copied \(urls.count) item(s)"
        logger.info("clipboard", "files.copied", metadata: metadataWithRequestID([
            "side": side.rawValue,
            "count": "\(urls.count)",
            "sources": urls.map(\.path).joined(separator: "|")
        ], requestID: requestID))
    }

    func pasteFileClipboard(into side: PaneSide, operation: FileClipboardOperation, requestID: String? = nil) {
        guard !isInlineRenaming else {
            logger.debug("file-operation", "paste.\(operation.rawValue).ignored", metadata: metadataWithRequestID([
                "side": side.rawValue,
                "reason": "inline-renaming"
            ], requestID: requestID))
            return
        }

        let sources = fileURLsFromPasteboard()
        guard !sources.isEmpty else {
            logger.debug("file-operation", "paste.\(operation.rawValue).ignored", metadata: metadataWithRequestID([
                "side": side.rawValue,
                "reason": "empty-file-clipboard"
            ], requestID: requestID))
            return
        }

        let destination = pane(for: side).selectedURL.standardizedFileURL
        let operableSources: [URL]
        if operation == .move {
            operableSources = sources.filter { $0.deletingLastPathComponent().standardizedFileURL != destination }
            let skippedCount = sources.count - operableSources.count
            if skippedCount > 0 {
                logger.debug("file-operation", "paste.move.skipped.same-destination", metadata: metadataWithRequestID([
                    "side": side.rawValue,
                    "destination": destination.path,
                    "count": "\(skippedCount)"
                ], requestID: requestID))
            }
        } else {
            operableSources = sources
        }

        guard !operableSources.isEmpty else {
            statusMessage = "No items to \(operation.rawValue) into this folder"
            logger.debug("file-operation", "paste.\(operation.rawValue).ignored", metadata: metadataWithRequestID([
                "side": side.rawValue,
                "destination": destination.path,
                "reason": "same-destination"
            ], requestID: requestID))
            return
        }

        logger.info("file-operation", "paste.\(operation.rawValue).requested", metadata: metadataWithRequestID([
            "side": side.rawValue,
            "count": "\(operableSources.count)",
            "destination": destination.path,
            "sources": operableSources.map(\.path).joined(separator: "|")
        ], requestID: requestID))

        enqueueFileOperation(
            operation == .copy ? .copy : .move,
            sources: operableSources,
            destination: destination
        )
    }

    func openInTerminal(_ urls: Set<URL>, on side: PaneSide) {
        let orderedURLs = orderedSelection(urls, on: side)
        let directories = uniqueDirectories(forTerminal: orderedURLs)
        guard !directories.isEmpty else { return }

        var openedCount = 0
        for directory in directories where openTerminal(at: directory) {
            openedCount += 1
            logger.info("terminal", "directory.opened", metadata: [
                "side": side.rawValue,
                "path": directory.path
            ])
        }

        if openedCount > 0 {
            statusMessage = "Opened \(openedCount) folder(s) in terminal"
        } else {
            statusMessage = "Failed to open terminal"
            logger.error("terminal", "directory.open.failed", metadata: [
                "side": side.rawValue,
                "count": "\(directories.count)"
            ])
        }
    }

    func previewSelection(on side: PaneSide) {
        let selected = pane(for: side).selectedItemURLs
        let urls = items(for: side).filter { selected.contains($0.url) }.map(\.url)
        guard !urls.isEmpty else { return }

        quickLookPreviewService.togglePreview(for: urls)
        statusMessage = "Previewing \(urls.count) item(s)"
        logger.info("quick-look", "selection.previewed", metadata: [
            "side": side.rawValue,
            "count": "\(urls.count)"
        ])
    }

    @discardableResult
    func previewAdjacentSelection(_ direction: PreviewNavigationDirection) -> Bool {
        let side = activePaneSide
        let itemURLs = items(for: side).map(\.url)
        let selected = pane(for: side).selectedItemURLs
        guard let nextURL = adjacentSelectionURL(
            in: itemURLs,
            selected: selected,
            direction: direction
        ) else {
            return false
        }

        setSelection([nextURL], for: side)
        quickLookPreviewService.togglePreview(for: [nextURL])
        statusMessage = "Previewing \(nextURL.lastPathComponent)"
        logger.info("quick-look", "selection.previewed.adjacent", metadata: [
            "side": side.rawValue,
            "direction": direction == .previous ? "previous" : "next",
            "path": nextURL.path
        ])
        return true
    }

    func adjacentSelectionURL(
        in itemURLs: [URL],
        selected: Set<URL>,
        direction: PreviewNavigationDirection
    ) -> URL? {
        guard !itemURLs.isEmpty else { return nil }

        let selectedIndexes = selected.compactMap { itemURLs.firstIndex(of: $0) }
        let currentIndex: Int
        switch direction {
        case .previous:
            currentIndex = selectedIndexes.min() ?? itemURLs.count
        case .next:
            currentIndex = selectedIndexes.max() ?? -1
        }

        let nextIndex = direction == .previous ? currentIndex - 1 : currentIndex + 1
        guard itemURLs.indices.contains(nextIndex) else { return nil }
        return itemURLs[nextIndex]
    }

    func navigateHome(_ side: PaneSide) {
        navigate(side, to: FileManager.default.homeDirectoryForCurrentUser)
    }

    func addTab(on side: PaneSide) {
        let id = mutatePane(side) { pane in
            pane.addTab(url: pane.selectedURL)
        }
        persistPaneSession()
        logger.info("tab", "tab.added", metadata: ["side": side.rawValue, "tab": id.uuidString])
        refresh(side)
    }

    @discardableResult
    func closeSelectedTab(on side: PaneSide) -> Bool {
        let tabID = pane(for: side).selectedTabID
        let didClose = mutatePane(side) { $0.closeTab(id: tabID) }
        if didClose {
            persistPaneSession()
            logger.info("tab", "tab.closed", metadata: ["side": side.rawValue, "tab": tabID.uuidString])
            refresh(side)
        } else {
            logger.debug("tab", "tab.close.ignored", metadata: ["side": side.rawValue, "tab": tabID.uuidString])
        }
        return didClose
    }

    @discardableResult
    func selectTab(_ id: UUID, on side: PaneSide) -> Bool {
        selectTab(id, on: side, requestID: nil, source: "ui", displayIndex: nil)
    }

    @discardableResult
    func selectTab(
        atZeroBasedIndex index: Int,
        on side: PaneSide,
        requestID: String,
        source: String
    ) -> Bool {
        logger.debug("tab", "tab.index-select.requested", metadata: [
            "requestID": requestID,
            "side": side.rawValue,
            "source": source,
            "index": "\(index)",
            "displayIndex": "\(index + 1)",
            "tabCount": "\(pane(for: side).tabs.count)"
        ])

        guard let tabID = pane(for: side).tabID(atZeroBasedIndex: index) else {
            logger.debug("tab", "tab.index-select.ignored", metadata: [
                "requestID": requestID,
                "side": side.rawValue,
                "source": source,
                "index": "\(index)",
                "displayIndex": "\(index + 1)",
                "tabCount": "\(pane(for: side).tabs.count)",
                "reason": "out-of-range"
            ])
            return false
        }

        return selectTab(tabID, on: side, requestID: requestID, source: source, displayIndex: index + 1)
    }

    @discardableResult
    private func selectTab(
        _ id: UUID,
        on side: PaneSide,
        requestID: String?,
        source: String,
        displayIndex: Int?
    ) -> Bool {
        guard pane(for: side).tabs.contains(where: { $0.id == id }) else { return false }
        activePaneSide = side
        mutatePane(side) { pane in
            pane.selectedTabID = id
            pane.selectedItemURLs.removeAll()
        }
        persistPaneSession()
        var metadata = [
            "side": side.rawValue,
            "tab": id.uuidString,
            "source": source
        ]
        if let requestID {
            metadata["requestID"] = requestID
        }
        if let displayIndex {
            metadata["displayIndex"] = "\(displayIndex)"
        }
        logger.info("tab", "tab.selected", metadata: metadata)
        refresh(side)
        return true
    }

    func chooseFolder(for side: PaneSide) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = pane(for: side).selectedURL
        if panel.runModal() == .OK, let url = panel.url {
            navigate(side, to: url)
        }
    }

    @discardableResult
    func createFolder(in side: PaneSide) -> URL? {
        let directory = pane(for: side).selectedURL
        do {
            let created = try operationService.createFolder(named: "New Folder", in: directory)
            statusMessage = "Created \(created.lastPathComponent)"
            refresh(side)
            setSelection([created], for: side)
            return created
        } catch {
            reportOperationFailure("folder.create.failed", error: error)
            return nil
        }
    }

    @discardableResult
    func createEmptyFile(named name: String, in side: PaneSide) -> URL? {
        let directory = pane(for: side).selectedURL
        do {
            let created = try operationService.createEmptyFile(named: name, in: directory)
            statusMessage = "Created \(created.lastPathComponent)"
            refresh(side)
            setSelection([created], for: side)
            return created
        } catch {
            reportOperationFailure("file.create.failed", error: error)
            return nil
        }
    }

    func renameItem(_ url: URL, to newName: String, on side: PaneSide) {
        do {
            let renamed = try operationService.rename(url, to: newName)
            statusMessage = "Renamed to \(renamed.lastPathComponent)"
            refresh(side)
            setSelection([renamed], for: side)
        } catch {
            reportOperationFailure("rename.failed", error: error)
        }
    }

    func selectedItems(on side: PaneSide) -> [FileItem] {
        let selected = pane(for: side).selectedItemURLs
        return items(for: side).filter { selected.contains($0.url) }
    }

    func batchRenamePreviews(rule: BatchRenameRule, on side: PaneSide) throws -> [BatchRenamePreview] {
        try BatchRenamePlanner().previews(for: selectedItems(on: side), rule: rule)
    }

    func applyBatchRename(_ previews: [BatchRenamePreview], on side: PaneSide) {
        guard !previews.isEmpty else { return }
        guard previews.allSatisfy({ $0.status.allowsApply }) else {
            statusMessage = "Fix preview errors before renaming"
            return
        }

        let operations = previews.map { BatchRenameOperation(sourceURL: $0.sourceURL, newName: $0.newName) }
        do {
            let renamedURLs = try operationService.batchRename(operations)
            refresh(side)
            setSelection(Set(renamedURLs), for: side)
            let changedCount = previews.filter(\.isChanged).count
            statusMessage = "Renamed \(changedCount) item(s)"
            logger.info("batch-rename", "applied", metadata: [
                "side": side.rawValue,
                "count": "\(changedCount)"
            ])
        } catch {
            reportOperationFailure("batch-rename.failed", error: error)
        }
    }

    func compareDirectories() {
        let left = leftPane.selectedURL
        let right = rightPane.selectedURL
        do {
            let results = try DirectoryComparisonService().compare(
                left: left,
                right: right,
                includeHidden: showHiddenFiles
            )
            directoryComparisonResults = results
            let changedCount = results.filter { $0.status != .same }.count
            statusMessage = "Compared folders: \(changedCount) difference(s)"
        } catch {
            reportOperationFailure("directory.compare.failed", error: error)
        }
    }

    func syncComparisonEntry(_ entry: DirectoryComparisonEntry, direction: PaneSide) {
        switch direction {
        case .left:
            guard let source = entry.rightURL else { return }
            enqueueDirectoryComparisonCopy(source: source, relativePath: entry.relativePath, destinationRoot: leftPane.selectedURL)
        case .right:
            guard let source = entry.leftURL else { return }
            enqueueDirectoryComparisonCopy(source: source, relativePath: entry.relativePath, destinationRoot: rightPane.selectedURL)
        }
    }

    private func enqueueDirectoryComparisonCopy(source: URL, relativePath: String, destinationRoot: URL) {
        let destinationParent = destinationRoot
            .appendingPathComponent(relativePath)
            .deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: destinationParent, withIntermediateDirectories: true)
            enqueueFileOperation(.copy, sources: [source], destination: destinationParent)
        } catch {
            reportOperationFailure("directory.sync.prepare.failed", error: error)
        }
    }

    func startGlobalSearch(query: String, searchContents: Bool) {
        let root = pane(for: activePaneSide).selectedURL
        let includeHidden = showHiddenFiles
        let cancellation = FileOperationCancellation()
        globalSearchCancellation?.cancel()
        globalSearchCancellation = cancellation
        isGlobalSearchRunning = true
        globalSearchResults = []
        statusMessage = "Searching \(root.path)..."

        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let results = try RecursiveFileSearchService().search(
                    root: root,
                    query: query,
                    options: RecursiveFileSearchOptions(includeHidden: includeHidden, searchContents: searchContents),
                    cancellation: cancellation,
                    progress: { scannedCount in
                        Task { @MainActor [weak self] in
                            guard self?.globalSearchCancellation === cancellation else { return }
                            self?.statusMessage = "Searching \(root.path)... \(scannedCount) scanned"
                        }
                    }
                )
                Task { @MainActor [weak self] in
                    guard self?.globalSearchCancellation === cancellation else { return }
                    self?.globalSearchResults = results
                    self?.isGlobalSearchRunning = false
                    self?.statusMessage = "Search completed: \(results.count) result(s)"
                }
            } catch FileOperationError.cancelled {
                Task { @MainActor [weak self] in
                    guard self?.globalSearchCancellation === cancellation else { return }
                    self?.isGlobalSearchRunning = false
                    self?.statusMessage = "Search cancelled"
                }
            } catch {
                Task { @MainActor [weak self] in
                    guard self?.globalSearchCancellation === cancellation else { return }
                    self?.isGlobalSearchRunning = false
                    self?.reportOperationFailure("global.search.failed", error: error)
                }
            }
        }
    }

    func cancelGlobalSearch() {
        globalSearchCancellation?.cancel()
    }

    func revealSearchResult(_ result: RecursiveFileSearchResult) {
        let side = activePaneSide
        navigate(side, to: result.url.deletingLastPathComponent(), selecting: result.url)
    }

    func copySelection(from sourceSide: PaneSide) {
        performSelectionOperation(from: sourceSide, operation: .copy)
    }

    func moveSelection(from sourceSide: PaneSide) {
        performSelectionOperation(from: sourceSide, operation: .move)
    }

    func trashSelection(from sourceSide: PaneSide) {
        let sources = orderedSelection(pane(for: sourceSide).selectedItemURLs, on: sourceSide)
        guard !sources.isEmpty else { return }
        let previewReplacementURL = quickLookPreviewService.isPreviewVisible
            ? FileSelectionResolver.replacementAfterRemoving(sources, from: items(for: sourceSide).map(\.url))
            : nil
        clearSelection(sourceSide)
        if quickLookPreviewService.isPreviewVisible {
            if let previewReplacementURL {
                setSelection([previewReplacementURL], for: sourceSide)
                quickLookPreviewService.showPreview(for: [previewReplacementURL])
            } else {
                quickLookPreviewService.closePreview()
            }
        }
        enqueueFileOperation(.trash, sources: sources, destination: nil)
    }

    func trashActiveSelection() {
        trashSelection(from: activePaneSide)
    }

    func emptyTrash() {
        guard !isInlineRenaming else { return }
        do {
            let removedCount = try operationService.emptyTrash()
            refreshAll()
            statusMessage = "Emptied Trash: \(removedCount) item(s)"
        } catch {
            reportOperationFailure("trash.empty.failed", error: error)
        }
    }

    func compressSelectionToZip(on side: PaneSide) {
        let sources = orderedSelection(pane(for: side).selectedItemURLs, on: side)
        guard !sources.isEmpty else { return }
        runArchiveOperation(label: "Compressing to ZIP", sources: sources, mode: nil)
    }

    func extractArchiveSelection(on side: PaneSide, mode: ArchiveExtractionMode) {
        let archives = orderedSelection(pane(for: side).selectedItemURLs, on: side)
        guard !archives.isEmpty else { return }
        let label = mode == .currentDirectory ? "Extracting here" : "Extracting to subfolder"
        runArchiveOperation(label: label, sources: archives, mode: mode)
    }

    func extractionSubfolderLabel(for url: URL) -> String {
        ArchiveFormatDetector.extractionFolderName(for: url)
    }

    func orderedContextMenuURLs(_ selection: Set<URL>, on side: PaneSide) -> [URL] {
        orderedSelection(selection, on: side)
    }

    private func runArchiveOperation(
        label: String,
        sources: [URL],
        mode: ArchiveExtractionMode?
    ) {
        guard !isInlineRenaming, !isArchiveOperationRunning else { return }

        let cancellation = FileOperationCancellation()
        archiveCancellation = cancellation
        isArchiveOperationRunning = true
        statusMessage = "\(label)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let service = ArchiveService(logger: nil)
            do {
                let successMessage: String
                if let mode {
                    try service.extract(archives: sources, mode: mode, cancellation: cancellation)
                    successMessage = mode == .currentDirectory
                        ? "Extracted archive(s) to current folder"
                        : "Extracted archive(s) to subfolder(s)"
                } else {
                    let created = try service.compressToZip(sources: sources, cancellation: cancellation)
                    successMessage = "Created archive: \(created.lastPathComponent)"
                }

                DispatchQueue.main.async {
                    self.isArchiveOperationRunning = false
                    self.archiveCancellation = nil
                    self.refreshAll()
                    self.statusMessage = successMessage
                }
            } catch ArchiveError.cancelled {
                DispatchQueue.main.async {
                    self.isArchiveOperationRunning = false
                    self.archiveCancellation = nil
                    self.statusMessage = "Archive operation cancelled"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isArchiveOperationRunning = false
                    self.archiveCancellation = nil
                    self.reportOperationFailure("archive.failed", error: error)
                }
            }
        }
    }

    func calculateSelectedFolderSizes(on side: PaneSide) {
        let selected = pane(for: side).selectedItemURLs
        let folders = items(for: side).filter { selected.contains($0.url) && $0.isDirectoryLike }
        guard !folders.isEmpty else { return }

        let cache = folderSizeCache
        let folderURLs = folders.map(\.url)
        statusMessage = "Calculating folder size for \(folders.count) folder(s)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let service = FileSystemService()
            var results: [(url: URL, size: Int64, source: String)] = []
            var failure: Error?

            for folderURL in folderURLs {
                do {
                    let result = try service.calculateFolderSize(at: folderURL, cache: cache)
                    let source: String
                    switch result {
                    case .cached:
                        source = "cache"
                    case .computed:
                        source = "computed"
                    }
                    results.append((folderURL, result.size, source))
                } catch {
                    failure = error
                    break
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let failure {
                    self.reportOperationFailure("folder.size.failed", error: failure)
                    return
                }

                let computed = results.filter { $0.source == "computed" }.count
                let cached = results.filter { $0.source == "cache" }.count
                for result in results {
                    self.logger.info("folder-size", "folder.size.resolved", metadata: [
                        "side": side.rawValue,
                        "path": result.url.path,
                        "bytes": "\(result.size)",
                        "source": result.source
                    ])
                }
                self.refresh(side)
                self.statusMessage = "Folder size: \(computed) computed, \(cached) cached"
            }
        }
    }

    func openLogFolder() {
        if let appLogger = logger as? AppLogger {
            NSWorkspace.shared.open(appLogger.logDirectory)
        }
    }

    func openFullDiskAccessSettings() {
        permissionGuide.openFullDiskAccessSettings()
        logger.info("privacy", "full-disk-access-settings.opened")
    }

    func dismissDiskAccessPrompt() {
        diskAccessPrompt = nil
    }

    func receiveDroppedFiles(_ sources: [URL], into side: PaneSide, move: Bool) {
        let destination = pane(for: side).selectedURL.standardizedFileURL
        let operableSources = move
            ? sources.filter { $0.deletingLastPathComponent().standardizedFileURL != destination }
            : sources
        guard !operableSources.isEmpty else { return }
        enqueueFileOperation(move ? .move : .copy, sources: operableSources, destination: destination)
    }

    func cancelFileOperation(_ id: UUID) {
        guard let request = pendingOperationRequests.first(where: { $0.id == id }) else { return }
        request.cancellation.cancel()
        updateQueuedOperation(id) { operation in
            if operation.status == .queued {
                operation.status = .cancelled
                operation.message = "Cancelled"
            }
        }
        pendingOperationRequests.removeAll { $0.id == id && fileOperationQueue.first(where: { $0.id == id })?.status == .cancelled }
        statusMessage = "Cancelling operation..."
    }

    func resolveFileConflict(_ resolution: FileOperationConflictResolution, applyToAll: Bool) {
        activeConflictAnswerBox?.resolve(FileConflictAnswer(resolution: resolution, applyToAll: applyToAll))
        activeConflictAnswerBox = nil
        fileConflictDialogRequest = nil
    }

    private func performSelectionOperation(from sourceSide: PaneSide, operation: QueuedFileOperationKind) {
        let sources = orderedSelection(pane(for: sourceSide).selectedItemURLs, on: sourceSide)
        guard !sources.isEmpty else {
            logger.debug("file-operation", "\(operation.rawValue).ignored.empty-selection", metadata: [
                "side": sourceSide.rawValue
            ])
            return
        }

        let destination = pane(for: opposite(sourceSide)).selectedURL
        logger.info("file-operation", "\(operation.rawValue).selection.requested", metadata: [
            "count": "\(sources.count)",
            "destination": destination.path,
            "side": sourceSide.rawValue
        ])

        clearSelection(sourceSide)
        enqueueFileOperation(operation, sources: sources, destination: destination)
    }

    private func enqueueFileOperation(_ kind: QueuedFileOperationKind, sources: [URL], destination: URL?) {
        let id = UUID()
        let cancellation = FileOperationCancellation()
        let request = QueuedFileOperationRequest(
            id: id,
            kind: kind,
            sources: sources,
            destination: destination,
            cancellation: cancellation
        )
        let operation = QueuedFileOperation(
            id: id,
            kind: kind,
            sources: sources,
            destination: destination,
            createdAt: Date(),
            status: .queued,
            progress: nil,
            message: "Queued",
            finishedAt: nil
        )
        pendingOperationRequests.append(request)
        fileOperationQueue.append(operation)
        statusMessage = "\(kind.displayName) queued: \(sources.count) item(s)"
        processNextFileOperationIfNeeded()
    }

    private func processNextFileOperationIfNeeded() {
        guard !isProcessingFileOperations, let request = pendingOperationRequests.first else { return }
        isProcessingFileOperations = true
        updateQueuedOperation(request.id) {
            $0.status = .running
            $0.message = "Running"
        }

        let id = request.id
        let kind = request.kind
        let sources = request.sources
        let destination = request.destination
        let cancellation = request.cancellation

        Task.detached(priority: .userInitiated) { [weak self] in
            let service = FileOperationService(logger: nil)
            var applyAllResolution: FileOperationConflictResolution?
            do {
                switch kind {
                case .copy:
                    guard let destination else { return }
                    try service.copy(
                        sources,
                        to: destination,
                        cancellation: cancellation,
                        progress: { progress in
                            Task { @MainActor [weak self] in
                                self?.recordFileOperationProgress(progress, for: id)
                            }
                        },
                        conflictResolver: { conflict in
                            if let applyAllResolution {
                                return applyAllResolution
                            }
                            let answer = self?.resolveConflictSynchronously(conflict)
                                ?? FileConflictAnswer(resolution: .keepBoth, applyToAll: false)
                            if answer.applyToAll {
                                applyAllResolution = answer.resolution
                            }
                            return answer.resolution
                        }
                    )
                case .move:
                    guard let destination else { return }
                    try service.move(
                        sources,
                        to: destination,
                        cancellation: cancellation,
                        progress: { progress in
                            Task { @MainActor [weak self] in
                                self?.recordFileOperationProgress(progress, for: id)
                            }
                        },
                        conflictResolver: { conflict in
                            if let applyAllResolution {
                                return applyAllResolution
                            }
                            let answer = self?.resolveConflictSynchronously(conflict)
                                ?? FileConflictAnswer(resolution: .keepBoth, applyToAll: false)
                            if answer.applyToAll {
                                applyAllResolution = answer.resolution
                            }
                            return answer.resolution
                        }
                    )
                case .trash:
                    try service.trash(
                        sources,
                        cancellation: cancellation,
                        progress: { progress in
                            Task { @MainActor [weak self] in
                                self?.recordFileOperationProgress(progress, for: id)
                            }
                        }
                    )
                }

                Task { @MainActor [weak self] in
                    self?.finishFileOperation(id, status: .completed, message: "\(kind.displayName) completed")
                }
            } catch FileOperationError.cancelled {
                Task { @MainActor [weak self] in
                    self?.finishFileOperation(id, status: .cancelled, message: "Cancelled")
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.finishFileOperation(id, status: .failed, message: error.localizedDescription)
                    self?.reportOperationFailure("\(kind.rawValue).failed", error: error)
                }
            }
        }
    }

    private func recordFileOperationProgress(_ progress: FileOperationProgress, for id: UUID) {
        updateQueuedOperation(id) {
            $0.progress = progress
            if let currentItem = progress.currentItem {
                $0.message = currentItem.lastPathComponent
            }
        }
    }

    private func finishFileOperation(_ id: UUID, status: QueuedFileOperationStatus, message: String) {
        updateQueuedOperation(id) {
            $0.status = status
            $0.message = message
            $0.finishedAt = Date()
        }
        pendingOperationRequests.removeAll { $0.id == id }
        isProcessingFileOperations = false
        refreshAll()
        statusMessage = message
        processNextFileOperationIfNeeded()
    }

    func clearFinishedFileOperations() {
        let activeIDs = Set(pendingOperationRequests.map(\.id))
        fileOperationQueue.removeAll { operation in
            !activeIDs.contains(operation.id)
                && (operation.status == .completed || operation.status == .failed || operation.status == .cancelled)
        }
        statusMessage = "Cleared operation history"
    }

    func canRetryFileOperation(_ id: UUID) -> Bool {
        guard let operation = fileOperationQueue.first(where: { $0.id == id }) else { return false }
        guard operation.status == .failed || operation.status == .cancelled else { return false }
        if operation.kind != .trash, operation.destination == nil { return false }
        return operation.sources.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func retryFileOperation(_ id: UUID) {
        guard let operation = fileOperationQueue.first(where: { $0.id == id }),
              canRetryFileOperation(id)
        else {
            statusMessage = "Cannot retry operation; source item is missing"
            return
        }

        let existingSources = operation.sources.filter { FileManager.default.fileExists(atPath: $0.path) }
        enqueueFileOperation(operation.kind, sources: existingSources, destination: operation.destination)
        logger.info("file-operation", "operation.retry.queued", metadata: [
            "originalID": id.uuidString,
            "kind": operation.kind.rawValue,
            "count": "\(existingSources.count)"
        ])
    }

    func recoverySuggestion(for operation: QueuedFileOperation) -> String {
        let existingSourceCount = operation.sources.filter { FileManager.default.fileExists(atPath: $0.path) }.count
        if existingSourceCount == 0 {
            return "Recovery unavailable: the source item no longer exists."
        }
        if operation.kind != .trash, operation.destination == nil {
            return "Recovery unavailable: the destination folder is missing from the operation record."
        }
        return "Fix the reported issue, then retry with \(existingSourceCount) available source item(s)."
    }

    private func updateQueuedOperation(_ id: UUID, mutate: (inout QueuedFileOperation) -> Void) {
        guard let index = fileOperationQueue.firstIndex(where: { $0.id == id }) else { return }
        mutate(&fileOperationQueue[index])
    }

    private nonisolated func resolveConflictSynchronously(_ conflict: FileOperationConflict) -> FileConflictAnswer {
        let box = FileConflictAnswerBox()
        Task { @MainActor [weak self] in
            self?.activeConflictAnswerBox = box
            self?.fileConflictDialogRequest = FileConflictDialogRequest(
                source: conflict.source,
                destination: conflict.destination
            )
        }
        return box.wait()
    }

    private func setItems(_ items: [FileItem], for side: PaneSide) {
        if side == .left {
            leftItems = items
        } else {
            rightItems = items
        }
    }

    @discardableResult
    private func mutatePane<T>(_ side: PaneSide, _ body: (inout PaneState) -> T) -> T {
        if side == .left {
            return body(&leftPane)
        }
        return body(&rightPane)
    }

    private func clearSelection(_ side: PaneSide) {
        setSelection([], for: side)
    }

    private func setSelection(_ selection: Set<URL>, for side: PaneSide) {
        if side == .left {
            leftPane.selectedItemURLs = selection
        } else {
            rightPane.selectedItemURLs = selection
        }
    }

    private func persistPaneSession() {
        paneSessionStore.save(left: leftPane, right: rightPane)
    }

    private func folderURL(fromPathText pathText: String, relativeTo baseURL: URL) -> URL {
        let expandedPath: String
        if pathText == "~" {
            expandedPath = FileManager.default.homeDirectoryForCurrentUser.path
        } else if pathText.hasPrefix("~/") {
            let suffix = String(pathText.dropFirst(2))
            expandedPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(suffix)
                .path
        } else {
            expandedPath = pathText
        }

        if expandedPath.hasPrefix("/") {
            return URL(fileURLWithPath: expandedPath).standardizedFileURL
        }

        return baseURL.appendingPathComponent(expandedPath).standardizedFileURL
    }

    private func orderedSelection(_ selection: Set<URL>, on side: PaneSide) -> [URL] {
        let itemURLs = items(for: side).map(\.url)
        let ordered = itemURLs.filter { selection.contains($0) }
        return ordered.isEmpty ? Array(selection).sorted { $0.path < $1.path } : ordered
    }

    private func fileURLsFromPasteboard() -> [URL] {
        let objects = NSPasteboard.general.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []

        return objects.compactMap { object in
            if let url = object as? URL {
                return url.standardizedFileURL
            }
            return (object as? NSURL)?.filePathURL?.standardizedFileURL
        }
    }

    private func metadataWithRequestID(_ metadata: [String: String], requestID: String?) -> [String: String] {
        guard let requestID else { return metadata }
        var enriched = metadata
        enriched["requestID"] = requestID
        return enriched
    }

    private func uniqueDirectories(forTerminal urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var directories: [URL] = []

        for url in urls {
            let directory = terminalDirectory(for: url).standardizedFileURL
            guard seen.insert(directory.path).inserted else { continue }
            directories.append(directory)
        }

        return directories
    }

    private func terminalDirectory(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private func openTerminal(at directory: URL) -> Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil,
           openGhosttyTab(at: directory) {
            return true
        }

        return runOpen(arguments: ["-a", "Terminal", directory.path])
    }

    private func openGhosttyTab(at directory: URL) -> Bool {
        let workingDirectory = appleScriptStringLiteral(directory.path)
        let script = """
        tell application "Ghostty"
            set surfaceConfig to new surface configuration from {initial working directory:\(workingDirectory)}
            if (count of windows) is greater than 0 then
                set newTab to new tab in front window with configuration surfaceConfig
                select tab newTab
            else
                new window with configuration surfaceConfig
            end if
            activate
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return true
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger.error("terminal", "ghostty.applescript.failed", metadata: [
                "path": directory.path,
                "error": errorMessage
            ])
            return false
        } catch {
            logger.error("terminal", "ghostty.applescript.failed", metadata: [
                "path": directory.path,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    private func appleScriptStringLiteral(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private func runOpen(arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger.error("terminal", "open.command.failed", metadata: [
                "arguments": arguments.joined(separator: " "),
                "error": error.localizedDescription
            ])
            return false
        }
    }

    private func opposite(_ side: PaneSide) -> PaneSide {
        side == .left ? .right : .left
    }

    private func openInFinder(_ url: URL) {
        logger.info("navigation", "file.opened.externally", metadata: ["path": url.path])
        NSWorkspace.shared.open(url)
    }

    private func reportOperationFailure(_ message: String, error: Error) {
        statusMessage = "\(message): \(error.localizedDescription)"
        logger.error("operation", message, metadata: ["error": error.localizedDescription])
        handlePossiblePermissionFailure(error, path: nil)
    }

    private func handlePossiblePermissionFailure(_ error: Error, path: String?) {
        guard permissionGuide.isFilePermissionDenied(error) else { return }

        let deniedPath = path ?? "the selected location"
        diskAccessPrompt = DiskAccessPrompt(
            path: deniedPath,
            message: "Dual Finder needs Full Disk Access to read protected folders such as Downloads, Desktop, Documents, and iCloud Drive. Enable it in System Settings, then restart the app."
        )

        logger.warning("privacy", "file-access.denied", metadata: [
            "path": deniedPath,
            "error": error.localizedDescription
        ])

        guard !didAutoOpenDiskAccessSettings else { return }
        didAutoOpenDiskAccessSettings = true
        openFullDiskAccessSettings()
    }
}
