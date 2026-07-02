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

struct SimilarFileDeletionMarkRequest: Equatable {
    let id = UUID()
    let side: PaneSide
    let urls: Set<URL>
}

struct FolderBookmarkDialogRequest: Identifiable, Equatable {
    let id = UUID()
}

struct BatchRenameDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
}

struct MergeFilesDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
    let sources: [URL]
    let suggestedName: String
}

struct SplitFileDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let side: PaneSide
    let preview: TextFileSplitPreview
}

struct EmptyTrashConfirmationRequest: Identifiable, Equatable {
    let id = UUID()
    let summary: TrashContentsSummary

    var formattedTotalSize: String {
        ByteCountFormatter.string(fromByteCount: summary.totalByteCount, countStyle: .file)
    }

    var message: String {
        """
        This will permanently delete \(summary.topLevelItemCount) item(s) from Trash.

        Contained files/folders: \(summary.containedItemCount)
        Total size: \(formattedTotalSize)
        """
    }
}

struct InlineRenameRequest: Equatable {
    let id = UUID()
    let side: PaneSide
    let url: URL
}

struct ShortcutHelpRequest: Identifiable, Equatable {
    let id = UUID()
}

enum FileClipboardOperation: String {
    case copy
    case move
}

private enum AndroidPaneTransferError: LocalizedError {
    case differentDevices

    var errorDescription: String? {
        switch self {
        case .differentDevices:
            "Android-to-Android transfer currently requires the same device."
        }
    }
}

private extension Notification.Name {
    static let pasteboardChanged = Notification.Name("NSPasteboardChangedNotification")
}

private final class TextEncodingScanCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

@MainActor
final class DualFinderViewModel: ObservableObject {
    @Published var leftPane: PaneState
    @Published var rightPane: PaneState
    @Published private(set) var leftItems: [FileItem] = []
    @Published private(set) var rightItems: [FileItem] = []
    @Published private(set) var leftFlatViewRootURL: URL?
    @Published private(set) var rightFlatViewRootURL: URL?
    @Published var statusMessage: String = ""
    @Published var diskAccessPrompt: DiskAccessPrompt?
    @Published var showWindowHotkeyPrompt: ShowWindowHotkeyPrompt?
    @Published private(set) var activePaneSide: PaneSide = .left
    @Published var pathEditRequest: PathEditRequest?
    @Published var paneFocusRequest: PaneFocusRequest?
    @Published var fileSearchRequest: FileSearchRequest?
    @Published var similarFileDeletionMarkRequest: SimilarFileDeletionMarkRequest?
    @Published var folderBookmarkDialogRequest: FolderBookmarkDialogRequest?
    @Published var batchRenameDialogRequest: BatchRenameDialogRequest?
    @Published var mergeFilesDialogRequest: MergeFilesDialogRequest?
    @Published var splitFileDialogRequest: SplitFileDialogRequest?
    @Published var emptyTrashConfirmationRequest: EmptyTrashConfirmationRequest?
    @Published var inlineRenameRequest: InlineRenameRequest?
    @Published private(set) var pasteboardRevision = 0
    @Published private(set) var fileOperationQueue: [QueuedFileOperation] = []
    @Published var fileConflictDialogRequest: FileConflictDialogRequest? {
        didSet {
            // If the dialog is dismissed without resolving the box (e.g. via the
            // sheet binding being set to nil outside of `resolveFileConflict`),
            // unblock the waiting file operation by resolving the box with a
            // default answer.
            if fileConflictDialogRequest == nil, oldValue != nil {
                activeConflictAnswerBox?.resolve(FileConflictAnswer(resolution: .skip, applyToAll: false))
                activeConflictAnswerBox = nil
            }
        }
    }
    @Published var directoryComparisonDialogRequest: DirectoryComparisonDialogRequest?
    @Published var globalSearchDialogRequest: GlobalSearchDialogRequest?
    @Published var shortcutHelpRequest: ShortcutHelpRequest?
    @Published private(set) var directoryComparisonResults: [DirectoryComparisonEntry] = []
    @Published private(set) var globalSearchResults: [RecursiveFileSearchResult] = []
    @Published private(set) var isGlobalSearchRunning = false
    @Published private(set) var androidDevices: [AndroidDevice] = []
    @Published var isInlineRenaming = false
    @Published private(set) var folderBookmarkRevision = 0
    @Published var showHiddenFiles = false {
        didSet { refreshAll() }
    }
    @Published private(set) var uiLayoutPreferences: UILayoutPreferences

    private let fileSystem: FileSystemService
    private let operationService: FileOperationService
    private let sortRuleStore: FolderSortRuleStore
    private let paneSessionStore: PaneSessionStore
    private let folderBookmarkStore: FolderBookmarkStore
    private let folderSizeCache: FolderSizeCache
    private let operationScanCache: OperationScanCache
    private let textEncodingCache: TextEncodingConversionCache
    private let androidFileService: AndroidFileService
    private let uiLayoutPreferencesStore: UILayoutPreferencesStore
    private let permissionGuide: PrivacyPermissionGuide
    private let quickLookPreviewService: QuickLookPreviewService
    private let logger: AppLogging
    private var didAutoOpenDiskAccessSettings = false
    private var pendingOperationRequests: [QueuedFileOperationRequest] = []
    private var isProcessingFileOperations = false
    private var activeConflictAnswerBox: FileConflictAnswerBox?
    private var similarFileReviewActiveSides: Set<PaneSide> = []
    private var leftFlatViewReturnSelection: Set<URL> = []
    private var rightFlatViewReturnSelection: Set<URL> = []
    private var androidPaneDevices: [PaneSide: String] = [:]
    private var localPaneReturnURLs: [PaneSide: URL] = [:]
    private var androidDevicesLastRefreshedAt: Date?
    private var globalSearchCancellation: FileOperationCancellation?
    private var archiveCancellation: FileOperationCancellation?
    private var textEncodingScanCancellations: [PaneSide: TextEncodingScanCancellation] = [:]
    private var isArchiveOperationRunning = false
    private var activeTabDrag: (tabID: UUID, sourceSide: PaneSide)?
    @Published private var isTextEncodingConversionRunning = false

    init(
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: FileSystemService = FileSystemService(),
        sortRuleStore: FolderSortRuleStore = FolderSortRuleStore(),
        paneSessionStore: PaneSessionStore = PaneSessionStore(),
        folderBookmarkStore: FolderBookmarkStore = FolderBookmarkStore(),
        folderSizeCache: FolderSizeCache = FolderSizeCache(),
        operationScanCache: OperationScanCache = OperationScanCache(),
        textEncodingCache: TextEncodingConversionCache = TextEncodingConversionCache(),
        uiLayoutPreferencesStore: UILayoutPreferencesStore = UILayoutPreferencesStore(),
        androidFileService: AndroidFileService? = nil,
        permissionGuide: PrivacyPermissionGuide = PrivacyPermissionGuide(),
        quickLookPreviewService: QuickLookPreviewService = QuickLookPreviewService(),
        logger: AppLogging
    ) {
        self.fileSystem = fileSystem
        self.sortRuleStore = sortRuleStore
        self.paneSessionStore = paneSessionStore
        self.folderBookmarkStore = folderBookmarkStore
        self.folderSizeCache = folderSizeCache
        self.operationScanCache = operationScanCache
        self.textEncodingCache = textEncodingCache
        self.androidFileService = androidFileService ?? AndroidFileService(logger: logger)
        self.uiLayoutPreferencesStore = uiLayoutPreferencesStore
        self.permissionGuide = permissionGuide
        self.quickLookPreviewService = quickLookPreviewService
        self.logger = logger
        let restoredPanes = paneSessionStore.load(fallbackURL: initialURL)
        leftPane = restoredPanes.left
        rightPane = restoredPanes.right
        uiLayoutPreferences = uiLayoutPreferencesStore.load()
        operationService = FileOperationService(logger: logger, operationScanCache: operationScanCache)
        self.quickLookPreviewService.navigationHandler = { [weak self] direction in
            self?.previewAdjacentSelection(direction) ?? false
        }
        logger.info("view-model", "initialized", metadata: [
            "initialURL": initialURL.path,
            "leftURL": leftPane.selectedURL.path,
            "rightURL": rightPane.selectedURL.path
        ])
        setupPasteboardObservation()
    }

    func items(for side: PaneSide) -> [FileItem] {
        side == .left ? leftItems : rightItems
    }

    func pane(for side: PaneSide) -> PaneState {
        side == .left ? leftPane : rightPane
    }

    func sortRule(for side: PaneSide) -> FileSortRule {
        sortRuleStore.rule(for: flatViewRoot(for: side) ?? pane(for: side).selectedURL)
    }

    func flatViewRoot(for side: PaneSide) -> URL? {
        side == .left ? leftFlatViewRootURL : rightFlatViewRootURL
    }

    func isFlatViewActive(on side: PaneSide) -> Bool {
        flatViewRoot(for: side) != nil
    }

    func isAndroidPane(_ side: PaneSide) -> Bool {
        androidPaneDevices[side] != nil
    }

    func androidDeviceSerial(for side: PaneSide) -> String? {
        androidPaneDevices[side]
    }

    func displayPath(for side: PaneSide) -> String {
        if let android = AndroidFileURL.parse(pane(for: side).selectedURL) {
            return "\(android.deviceSerial):\(android.path)"
        }
        return pane(for: side).selectedURL.path
    }

    func columnWidths(for side: PaneSide) -> FileListColumnWidths {
        uiLayoutPreferences.columnWidths(for: side)
    }

    var isEncodingColumnVisible: Bool {
        uiLayoutPreferences.isEncodingColumnVisible
    }

    func setEncodingColumnVisible(_ isVisible: Bool) {
        guard uiLayoutPreferences.isEncodingColumnVisible != isVisible else { return }
        var preferences = uiLayoutPreferences
        preferences.isEncodingColumnVisible = isVisible
        persistUILayoutPreferences(preferences)
        if isVisible {
            refreshAll()
        } else {
            cancelTextEncodingScans()
        }
    }

    func adjustFileListColumn(_ column: FileListColumn, for side: PaneSide, by delta: CGFloat) {
        var preferences = uiLayoutPreferences
        var widths = preferences.columnWidths(for: side)
        widths.adjust(column, by: Double(delta))
        preferences.setColumnWidths(widths, for: side)
        uiLayoutPreferences = preferences
    }

    func setLeftPaneFraction(_ fraction: Double) {
        var preferences = uiLayoutPreferences
        preferences.leftPaneFraction = UILayoutPreferences.clampedFraction(fraction)
        uiLayoutPreferences = preferences
    }

    func commitUILayoutPreferences() {
        uiLayoutPreferencesStore.save(uiLayoutPreferences)
    }

    func setSidebarCollapsed(_ isCollapsed: Bool) {
        var preferences = uiLayoutPreferences
        preferences.isSidebarCollapsed = isCollapsed
        persistUILayoutPreferences(preferences)
    }

    func toggleSidebarCollapsed() {
        setSidebarCollapsed(!uiLayoutPreferences.isSidebarCollapsed)
    }

    private func persistUILayoutPreferences(_ preferences: UILayoutPreferences) {
        uiLayoutPreferences = preferences
        uiLayoutPreferencesStore.save(preferences)
    }

    var hasActiveSelection: Bool {
        hasSelection(on: activePaneSide)
    }

    func hasSelection(on side: PaneSide) -> Bool {
        !pane(for: side).selectedItemURLs.isEmpty
    }

    var activeSelectionCount: Int {
        pane(for: activePaneSide).selectedItemURLs.count
    }

    var activeItemCount: Int {
        items(for: activePaneSide).count
    }

    var canCopyActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        return MenuActionAvailability.canCopyFiles(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canPasteToActivePane: Bool {
        _ = pasteboardRevision
        return MenuActionAvailability.canPasteFiles(
            pasteboardHasFileURLs: FilePasteboardReader.hasFileURLs,
            isInlineRenaming: isInlineRenaming,
            isArchiveOperationRunning: isArchiveOperationRunning
        )
    }

    var canTrashActiveSelection: Bool {
        MenuActionAvailability.canTrashSelection(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canEmptyTrash: Bool {
        MenuActionAvailability.canEmptyTrash(
            isInlineRenaming: isInlineRenaming,
            isArchiveOperationRunning: isArchiveOperationRunning
        )
    }

    var canCopyAbsolutePathActiveSelection: Bool {
        return MenuActionAvailability.canCopyAbsolutePath(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canSelectAllInActivePane: Bool {
        MenuActionAvailability.canSelectAll(
            itemCount: activeItemCount,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canRenameActiveSelection: Bool {
        MenuActionAvailability.canRenameSelection(
            selectionCount: activeSelectionCount,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canBatchRenameActiveSelection: Bool {
        MenuActionAvailability.canBatchRename(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canExtractFilenameFromContentActiveSelection: Bool {
        MenuActionAvailability.canExtractFilenameFromContent(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canOpenActiveSelection: Bool {
        MenuActionAvailability.canOpenSelection(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canQuickLookActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        return MenuActionAvailability.canQuickLook(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canCreateInActivePane: Bool {
        MenuActionAvailability.canCreateItems(
            isInlineRenaming: isInlineRenaming,
            isArchiveOperationRunning: isArchiveOperationRunning
        )
    }

    var canNavigateBackActivePane: Bool {
        MenuActionAvailability.canNavigateHistory(
            canNavigate: pane(for: activePaneSide).canNavigateSelectedTabBack,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canNavigateForwardActivePane: Bool {
        MenuActionAvailability.canNavigateHistory(
            canNavigate: pane(for: activePaneSide).canNavigateSelectedTabForward,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canCopyFromLeftPane: Bool {
        MenuActionAvailability.canTransferToOtherPane(
            hasSelection: hasSelection(on: .left),
            isInlineRenaming: isInlineRenaming,
            isArchiveOperationRunning: isArchiveOperationRunning
        )
    }

    var canCopyFromRightPane: Bool {
        MenuActionAvailability.canTransferToOtherPane(
            hasSelection: hasSelection(on: .right),
            isInlineRenaming: isInlineRenaming,
            isArchiveOperationRunning: isArchiveOperationRunning
        )
    }

    var canMoveFromLeftPane: Bool { canCopyFromLeftPane }
    var canMoveFromRightPane: Bool { canCopyFromRightPane }

    var canOpenTerminalActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        return MenuActionAvailability.canOpenInTerminal(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canShareActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        return MenuActionAvailability.canShare(
            hasSelection: hasActiveSelection,
            isInlineRenaming: isInlineRenaming
        )
    }

    var canOpenInNewTabsActiveSelection: Bool {
        let side = activePaneSide
        return allSelectedItemsAreDirectories(
            in: pane(for: side).selectedItemURLs,
            on: side
        ) && !isInlineRenaming
    }

    var canAddFavoriteFromActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        let side = activePaneSide
        let directories = selectedDirectoryURLs(
            in: pane(for: side).selectedItemURLs,
            on: side
        )
        guard !directories.isEmpty else { return false }
        let hasUnfavorited = directories.contains { !isFolderFavorite($0) }
        return hasUnfavorited && !isInlineRenaming
    }

    var canCompressActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        guard !isInlineRenaming, !isArchiveOperationRunning, hasActiveSelection else { return false }
        let urls = orderedSelection(pane(for: activePaneSide).selectedItemURLs, on: activePaneSide)
        return ArchiveService.canCompress(urls)
    }

    var canExtractActiveSelection: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        guard !isInlineRenaming, !isArchiveOperationRunning, hasActiveSelection else { return false }
        let urls = orderedSelection(pane(for: activePaneSide).selectedItemURLs, on: activePaneSide)
        return ArchiveService.hasExtractableArchives(urls)
    }

    var canConvertActiveSelectionToUTF8: Bool {
        guard !isAndroidPane(activePaneSide) else { return false }
        return hasActiveSelection
            && !isInlineRenaming
            && !isArchiveOperationRunning
            && !isTextEncodingConversionRunning
    }

    var canMergeActiveSelection: Bool {
        canMergeFiles(in: pane(for: activePaneSide).selectedItemURLs, on: activePaneSide)
    }

    var canSplitActiveSelection: Bool {
        canSplitFile(in: pane(for: activePaneSide).selectedItemURLs, on: activePaneSide)
    }

    func selectAllItems(on side: PaneSide) {
        activatePane(side)
        let urls = Set(items(for: side).map(\.url))
        setSelection(urls, for: side)
        statusMessage = "Selected \(urls.count) item(s)"
        logger.debug("selection", "select-all", metadata: [
            "side": side.rawValue,
            "count": "\(urls.count)"
        ])
    }

    func requestInlineRenameActiveSelection() {
        let side = activePaneSide
        let selected = pane(for: side).selectedItemURLs
        guard canRenameActiveSelection,
              let url = orderedSelection(selected, on: side).first else { return }
        requestInlineRename(for: url, on: side)
    }

    func requestInlineRename(for url: URL, on side: PaneSide) {
        activatePane(side)
        inlineRenameRequest = InlineRenameRequest(side: side, url: url)
    }

    func createFolderAndRequestRename(in side: PaneSide) {
        guard MenuActionAvailability.canCreateItems(
            isInlineRenaming: isInlineRenaming,
            isArchiveOperationRunning: isArchiveOperationRunning
        ) else { return }

        if let created = createFolder(in: side) {
            requestInlineRename(for: created, on: side)
        }
    }

    func shareActiveSelection() {
        shareItems([], on: activePaneSide)
    }

    func addSelectedDirectoriesToFavorites(on side: PaneSide) {
        let directories = selectedDirectoryURLs(
            in: pane(for: side).selectedItemURLs,
            on: side
        )
        guard !directories.isEmpty else { return }

        var addedCount = 0
        for url in directories where !isFolderFavorite(url) {
            addFolderToFavorites(url)
            addedCount += 1
        }
        if addedCount == 0 {
            statusMessage = "Selected folders are already favorites"
        }
    }

    func bindingForSelection(side: PaneSide) -> Binding<Set<URL>> {
        Binding(
            get: { self.pane(for: side).selectedItemURLs },
            set: { newValue in
                self.activatePane(side)
                guard self.pane(for: side).selectedItemURLs != newValue else { return }

                self.setSelection(newValue, for: side)
                self.logger.debug(
                    "selection",
                    "selection.changed",
                    metadata: self.selectionLogMetadata(newValue, side: side)
                )
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

    func logSelectionPerformanceEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("selection-performance", message, metadata: metadata)
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

    func refreshAndroidDevices(refreshedAt: Date = Date()) {
        androidDevicesLastRefreshedAt = refreshedAt
        do {
            androidDevices = try androidFileService.devices()
            statusMessage = androidDevices.isEmpty
                ? "No Android devices connected"
                : "Android devices: \(androidDevices.count)"
            logger.info("android", "devices.refreshed", metadata: [
                "count": "\(androidDevices.count)"
            ])
        } catch {
            reportOperationFailure("android.devices.failed", error: error)
        }
    }

    func refreshAndroidDevicesForToolbar(now: Date = Date(), staleAfter: TimeInterval = 5) {
        guard !isInlineRenaming else { return }
        if let androidDevicesLastRefreshedAt,
           now.timeIntervalSince(androidDevicesLastRefreshedAt) < staleAfter {
            return
        }
        refreshAndroidDevices(refreshedAt: now)
    }

    func refreshAndroidStateForViewButton(on side: PaneSide) {
        guard !isInlineRenaming else { return }
        activatePane(side)
        refreshAndroidDevices()
        if isAndroidPane(side) {
            refresh(side)
        }
    }

    func switchPaneToAndroid(_ side: PaneSide, deviceSerial requestedSerial: String? = nil) {
        guard !isInlineRenaming else { return }
        activatePane(side)

        let serial: String
        if let requestedSerial {
            serial = requestedSerial
        } else {
            refreshAndroidDevices()
            guard let connected = androidDevices.first(where: { $0.state == .device }) else {
                statusMessage = "No available Android device"
                return
            }
            serial = connected.serial
        }

        if !isAndroidPane(side) {
            localPaneReturnURLs[side] = pane(for: side).selectedURL
        }
        androidPaneDevices[side] = serial
        clearFlatViewState(on: side)
        let url = AndroidFileURL.url(deviceSerial: serial, path: "/sdcard")
        mutatePane(side) { pane in
            pane.navigateSelectedTab(to: url)
            pane.selectedItemURLs.removeAll()
        }
        refresh(side)
        logger.info("android", "pane.enabled", metadata: [
            "side": side.rawValue,
            "device": serial
        ])
    }

    func switchPaneToLocal(_ side: PaneSide) {
        guard isAndroidPane(side) else { return }
        let restoredURL = localPaneReturnURLs[side] ?? FileManager.default.homeDirectoryForCurrentUser
        androidPaneDevices[side] = nil
        localPaneReturnURLs[side] = nil
        mutatePane(side) { pane in
            pane.navigateSelectedTab(to: restoredURL)
            pane.selectedItemURLs.removeAll()
        }
        persistPaneSession()
        refresh(side)
        statusMessage = "Local view: \(restoredURL.path)"
    }

    func toggleFlatView(on side: PaneSide) {
        guard !isInlineRenaming else { return }
        activatePane(side)

        if isFlatViewActive(on: side) {
            exitFlatView(on: side)
            return
        }

        guard let root = flatViewRootCandidate(on: side) else { return }
        enterFlatView(root: root, on: side)
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

    func requestMergeFilesDialog(on side: PaneSide, urls: [URL] = []) {
        guard !isInlineRenaming, !isAndroidPane(side) else { return }
        let sources = urls.isEmpty
            ? mergeableFileURLs(in: pane(for: side).selectedItemURLs, on: side)
            : mergeableFileURLs(urls, on: side)
        guard sources.count >= 2 else {
            statusMessage = "Select at least two files to merge"
            return
        }

        activatePane(side)
        mergeFilesDialogRequest = MergeFilesDialogRequest(
            side: side,
            sources: sources,
            suggestedName: FileMergeNaming.suggestedName(for: sources)
        )
        logger.info("file-operation", "merge.dialog.requested", metadata: [
            "side": side.rawValue,
            "count": "\(sources.count)"
        ])
    }

    func requestSplitFileDialog(on side: PaneSide, urls: [URL] = []) {
        guard !isInlineRenaming, !isAndroidPane(side) else { return }
        let selected = urls.isEmpty ? orderedSelection(pane(for: side).selectedItemURLs, on: side) : urls
        guard canSplitFile(selected, on: side), let source = selected.first else {
            statusMessage = "Select one TXT file to split"
            return
        }

        do {
            let preview = try TextFileSplitService().previewSplit(for: source)
            activatePane(side)
            splitFileDialogRequest = SplitFileDialogRequest(side: side, preview: preview)
            statusMessage = "Split preview: \(preview.chapters.count) file(s)"
            logger.info("file-operation", "split-file.dialog.requested", metadata: [
                "side": side.rawValue,
                "source": source.path,
                "count": "\(preview.chapters.count)",
                "encoding": preview.detectedEncoding
            ])
        } catch {
            reportOperationFailure("split-file.preview.failed", error: error)
        }
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

    func requestShortcutHelp() {
        guard !isInlineRenaming else { return }
        shortcutHelpRequest = ShortcutHelpRequest()
        logger.debug("shortcut-help", "requested", metadata: [:])
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

    func logSimilarFileReviewEvent(_ message: String, metadata: [String: String] = [:]) {
        logger.debug("similar-file-review", message, metadata: metadata)
    }

    func setSimilarFileReviewActive(_ isActive: Bool, on side: PaneSide) {
        if isActive {
            similarFileReviewActiveSides.insert(side)
        } else {
            similarFileReviewActiveSides.remove(side)
        }
        logger.debug("similar-file-review", "active-state.changed", metadata: [
            "side": side.rawValue,
            "active": "\(isActive)"
        ])
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

    func canMergeFiles(in selection: Set<URL>, on side: PaneSide) -> Bool {
        guard !isAndroidPane(side), !isInlineRenaming else { return false }
        return mergeableFileURLs(in: selection, on: side).count >= 2
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

    func unmountVolume(_ url: URL) {
        let displayName = url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
        statusMessage = "Unmounting \(displayName)..."
        logger.info("volume", "unmount.requested", metadata: [
            "path": url.path
        ])

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                switch result {
                case .success:
                    self.statusMessage = "Unmounted \(displayName)"
                    self.logger.info("volume", "unmount.completed", metadata: [
                        "path": url.path
                    ])
                case .failure(let error):
                    self.statusMessage = "Could not unmount \(displayName)"
                    self.logger.error("volume", "unmount.failed", metadata: [
                        "path": url.path,
                        "error": error.localizedDescription
                    ])
                }
            }
        }
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
        logger.debug(
            "selection",
            "selection.replaced",
            metadata: selectionLogMetadata(selection, side: side, source: source)
        )
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

    func checkShowWindowHotkeyOnLaunch() {
        guard HotkeyHelperLoginItem.embeddedHelperURL() != nil else { return }
        guard !HotkeyHelperLoginItem.isRegistered else { return }
        guard UserDefaults.standard.bool(forKey: HotkeyHelperLoginItem.registrationAttemptedKey) else { return }
        guard showWindowHotkeyPrompt == nil else { return }

        showWindowHotkeyPrompt = ShowWindowHotkeyPrompt(
            message: """
            Enable the Dual Finder hotkey helper so \(ShowWindowHotkeyStore().binding().displayLabel) works even when the app is quit. \
            Approve “DualFinderHotkeyHelper” under Settings → General → Login Items. \
            \(PrivacyPermissionGuide.showWindowHotkeyNotes)
            """
        )
        logger.info("privacy", "show-window-hotkey.prompt", metadata: [
            "binding": ShowWindowHotkeyStore().binding().displayLabel
        ])
    }

    func openShowWindowHotkeySettings() {
        HotkeyHelperLoginItem.openLoginItemsSettings()
    }

    func retryShowWindowHotkeyHelperRegistration() {
        let registered = HotkeyHelperLoginItem.register()
        if registered {
            showWindowHotkeyPrompt = nil
            statusMessage = "Global \(ShowWindowHotkeyStore().binding().displayLabel) hotkey helper enabled."
        } else {
            statusMessage = "Could not enable hotkey helper. Open Login Items and allow DualFinderHotkeyHelper."
            openShowWindowHotkeySettings()
        }
        logger.info("privacy", "show-window-hotkey.retry", metadata: [
            "registered": "\(registered)"
        ])
    }

    func dismissShowWindowHotkeyPrompt() {
        showWindowHotkeyPrompt = nil
    }

    func refresh(_ side: PaneSide) {
        if isAndroidPane(side) {
            refreshAndroidDirectory(on: side)
            return
        }

        if let flatRoot = flatViewRoot(for: side) {
            refreshFlatView(root: flatRoot, on: side)
            return
        }

        let currentURL = pane(for: side).selectedURL.standardizedFileURL
        if let existingDirectory = fileSystem.existingDirectoryAncestor(startingAt: currentURL),
           existingDirectory != currentURL {
            navigateToExistingLocalDirectory(
                side,
                to: existingDirectory,
                source: "refresh.recovered-missing-directory"
            )
            return
        }

        do {
            let rule = sortRuleStore.rule(for: currentURL)
            let nextItems = try fileSystem.contents(
                of: currentURL,
                includeHidden: showHiddenFiles,
                sortRule: rule,
                folderSizeCache: folderSizeCache,
                textEncodingCache: textEncodingCache,
                includeTextEncoding: uiLayoutPreferences.isEncodingColumnVisible
            )
            setItems(nextItems, for: side)
            startTextEncodingScanIfNeeded(for: side, items: nextItems)
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
        let folder = flatViewRoot(for: side) ?? pane(for: side).selectedURL
        let nextRule = sortRuleStore.rule(for: folder).selecting(field)
        sortRuleStore.setRule(nextRule, for: folder)
        logger.info("sorting", "sort.changed", metadata: [
            "side": side.rawValue,
            "path": folder.path,
            "sort": "\(nextRule.field.rawValue).\(nextRule.direction.rawValue)"
        ])
        refresh(side)
    }

    private func refreshAndroidDirectory(on side: PaneSide) {
        guard let parsed = AndroidFileURL.parse(pane(for: side).selectedURL) else {
            setItems([], for: side)
            statusMessage = "Android path is invalid"
            return
        }

        do {
            let nextItems = try androidFileService.contents(
                of: parsed.path,
                on: parsed.deviceSerial,
                includeHidden: showHiddenFiles
            )
            setItems(nextItems, for: side)
            statusMessage = "\(parsed.deviceSerial):\(parsed.path) - \(nextItems.count) items"
            logger.info("android", "directory.refreshed", metadata: [
                "side": side.rawValue,
                "device": parsed.deviceSerial,
                "path": parsed.path,
                "count": "\(nextItems.count)"
            ])
        } catch {
            setItems([], for: side)
            reportOperationFailure("android.refresh.failed", error: error)
        }
    }

    private func navigateAndroid(_ side: PaneSide, to url: URL, selecting selection: URL? = nil) {
        guard let parsed = AndroidFileURL.parse(url) else {
            statusMessage = "Invalid Android path"
            return
        }

        if let item = items(for: side).first(where: { $0.url == url }), !item.isDirectoryLike {
            setSelection([url], for: side)
            statusMessage = "Selected \(item.name)"
            return
        }

        clearFlatViewState(on: side)
        androidPaneDevices[side] = parsed.deviceSerial
        mutatePane(side) { $0.navigateSelectedTab(to: url, selecting: selection) }
        logger.info("android", "directory.changed", metadata: [
            "side": side.rawValue,
            "device": parsed.deviceSerial,
            "path": parsed.path
        ])
        refresh(side)
    }

    func navigate(_ side: PaneSide, to url: URL, selecting selection: URL? = nil) {
        if isAndroidPane(side) || url.scheme == AndroidFileURL.scheme {
            navigateAndroid(side, to: url, selecting: selection)
            return
        }

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            openInFinder(url)
            return
        }
        clearFlatViewState(on: side)
        mutatePane(side) { $0.navigateSelectedTab(to: url, selecting: selection) }
        folderBookmarkStore.recordRecentFolder(url)
        persistPaneSession()
        logger.info("navigation", "directory.changed", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
        refresh(side)
    }

    private func navigateToExistingLocalDirectory(
        _ side: PaneSide,
        to url: URL,
        selecting selection: URL? = nil,
        source: String
    ) {
        let directory = url.standardizedFileURL
        clearFlatViewState(on: side)
        mutatePane(side) { $0.navigateSelectedTab(to: directory, selecting: selection) }
        folderBookmarkStore.recordRecentFolder(directory)
        persistPaneSession()
        logger.info("navigation", source, metadata: [
            "side": side.rawValue,
            "path": directory.path,
            "selection": selection?.path ?? ""
        ])
        refresh(side)
    }

    func navigateBack(_ side: PaneSide) {
        guard !isInlineRenaming else { return }
        guard let url = mutatePane(side, { $0.navigateSelectedTabBack() }) else {
            logger.debug("navigation", "history.back.ignored", metadata: ["side": side.rawValue])
            return
        }

        reconcilePaneModeAfterHistoryNavigation(to: url, on: side)
        clearFlatViewState(on: side)
        if url.scheme != AndroidFileURL.scheme {
            folderBookmarkStore.recordRecentFolder(url)
            persistPaneSession()
        }
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

        reconcilePaneModeAfterHistoryNavigation(to: url, on: side)
        clearFlatViewState(on: side)
        if url.scheme != AndroidFileURL.scheme {
            folderBookmarkStore.recordRecentFolder(url)
            persistPaneSession()
        }
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

        if isAndroidPane(side) {
            guard let serial = androidDeviceSerial(for: side) else { return false }
            let currentPath = AndroidFileURL.parse(pane(for: side).selectedURL)?.path ?? "/sdcard"
            let nextPath = trimmedPath.hasPrefix("/")
                ? AndroidFileURL.normalizedPath(trimmedPath)
                : AndroidFileURL.appending(trimmedPath, to: currentPath)
            navigate(side, to: AndroidFileURL.url(deviceSerial: serial, path: nextPath))
            return true
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
        if isAndroidPane(side) {
            guard let parsed = AndroidFileURL.parse(pane(for: side).selectedURL),
                  let parent = AndroidFileURL.parent(of: parsed.path) else { return }
            navigate(side, to: AndroidFileURL.url(deviceSerial: parsed.deviceSerial, path: parent))
            return
        }

        let currentURL = pane(for: side).selectedURL.standardizedFileURL
        guard let parent = fileSystem.parent(of: currentURL),
              let existingParent = fileSystem.existingDirectoryAncestor(startingAt: parent)
        else { return }

        let selection = existingParent == parent ? currentURL : nil
        navigateToExistingLocalDirectory(
            side,
            to: existingParent,
            selecting: selection,
            source: "navigate.up"
        )
    }

    func navigateIntoSelectedDirectory(_ side: PaneSide) {
        let selected = pane(for: side).selectedItemURLs
        guard let directory = items(for: side).first(where: { selected.contains($0.url) && $0.isDirectoryLike }) else {
            return
        }
        navigate(side, to: directory.url)
    }

    func openSelectionWithDefaultApp(on side: PaneSide) {
        guard !isAndroidPane(side) else {
            statusMessage = "Android files cannot be opened with local apps"
            return
        }

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

        let paths = orderedURLs.map { PathWithSizeClipboardFormat.absolutePath(for: $0) }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
        statusMessage = paths.count == 1 ? "Copied path: \(paths[0])" : "Copied \(paths.count) paths"
        logger.info("clipboard", "absolute-paths.copied", metadata: [
            "side": side.rawValue,
            "count": "\(paths.count)"
        ])
    }

    func copyPathsWithSizes(_ urls: Set<URL>, on side: PaneSide) {
        let orderedURLs = orderedSelection(urls, on: side)
        guard !orderedURLs.isEmpty else { return }

        statusMessage = "Copying paths with sizes..."
        let itemsByURL = Dictionary(uniqueKeysWithValues: items(for: side).map { ($0.url, $0) })
        let cache = folderSizeCache
        let isAndroid = isAndroidPane(side)

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let service = FileSystemService()
            var lines: [String] = []
            var needsRefresh = false

            for url in orderedURLs {
                let path = PathWithSizeClipboardFormat.absolutePath(for: url)
                let item = itemsByURL[url]
                var size = item?.size

                if size == nil, !isAndroid {
                    do {
                        let resolved = try PathWithSizeClipboardFormat.resolveByteSize(
                            for: url,
                            cachedItemSize: item?.size,
                            isDirectoryLike: item?.isDirectoryLike,
                            fileSystemService: service,
                            folderSizeCache: cache
                        )
                        if resolved != nil, item?.size == nil {
                            needsRefresh = true
                        }
                        size = resolved
                    } catch {
                        let errorDescription = error.localizedDescription
                        DispatchQueue.main.async {
                            self.logger.error("clipboard", "path-with-size.resolve-failed", metadata: [
                                "side": side.rawValue,
                                "path": path,
                                "error": errorDescription
                            ])
                        }
                    }
                }

                lines.append(PathWithSizeClipboardFormat.line(path: path, size: size))
            }

            DispatchQueue.main.async {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
                if needsRefresh {
                    self.refresh(side)
                }
                self.statusMessage = lines.count == 1
                    ? "Copied path with size: \(lines[0])"
                    : "Copied \(lines.count) paths with sizes"
                self.logger.info("clipboard", "paths-with-size.copied", metadata: [
                    "side": side.rawValue,
                    "count": "\(lines.count)"
                ])
            }
        }
    }

    func copySelectionToFileClipboard(on side: PaneSide, requestID: String? = nil) {
        guard !isAndroidPane(side) else {
            copyAbsolutePaths(pane(for: side).selectedItemURLs, on: side)
            logger.debug("clipboard", "android-files.copy-as-paths", metadata: metadataWithRequestID([
                "side": side.rawValue
            ], requestID: requestID))
            return
        }

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
        pasteboardRevision &+= 1
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

        if isAndroidPane(side) {
            let move = operation == .move
            receiveDroppedFiles(sources, into: side, move: move)
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
        guard !isAndroidPane(side) else {
            statusMessage = "Quick Look is local-only"
            return
        }

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
        if let serial = androidDeviceSerial(for: side) {
            navigate(side, to: AndroidFileURL.url(deviceSerial: serial, path: "/sdcard"))
            return
        }
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

    func beginTabDrag(tabID: UUID, on side: PaneSide) {
        activeTabDrag = (tabID, side)
        logger.debug("tab", "tab.drag.began", metadata: [
            "side": side.rawValue,
            "tab": tabID.uuidString
        ])
    }

    func endTabDrag() {
        if let activeTabDrag {
            logger.debug("tab", "tab.drag.ended", metadata: [
                "side": activeTabDrag.sourceSide.rawValue,
                "tab": activeTabDrag.tabID.uuidString
            ])
        }
        activeTabDrag = nil
    }

    var activeTabDragContext: (tabID: UUID, sourceSide: PaneSide)? {
        activeTabDrag
    }

    func reorderTabDuringDrag(tabID: UUID, on side: PaneSide, beforeTabID: UUID?) {
        let moved = mutatePane(side) { $0.moveTab(id: tabID, beforeTabID: beforeTabID) }
        guard moved else { return }
        persistPaneSession()
        refresh(side)
    }

    func moveTabDuringDrag(tabID: UUID, from sourceSide: PaneSide, to targetSide: PaneSide, beforeTabID: UUID?) {
        if sourceSide == targetSide {
            reorderTabDuringDrag(tabID: tabID, on: sourceSide, beforeTabID: beforeTabID)
            return
        }

        let replacementURL = fallbackTabURL(for: sourceSide)
        let detachedTab = mutatePane(sourceSide) {
            $0.detachTab(id: tabID, replacementURLIfEmpty: replacementURL)
        }
        guard let tab = detachedTab else { return }

        mutatePane(targetSide) { $0.insertTab(tab, beforeTabID: beforeTabID) }
        activePaneSide = targetSide
        persistPaneSession()
        logger.info("tab", "tab.moved", metadata: [
            "tab": tabID.uuidString,
            "from": sourceSide.rawValue,
            "to": targetSide.rawValue
        ])
        refresh(sourceSide)
        refresh(targetSide)
    }

    private func fallbackTabURL(for side: PaneSide) -> URL {
        if let serial = androidDeviceSerial(for: side) {
            return AndroidFileURL.url(deviceSerial: serial, path: "/sdcard")
        }
        return FileManager.default.homeDirectoryForCurrentUser
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
        if isAndroidPane(side) {
            return createAndroidFolder(in: side)
        }

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
        if isAndroidPane(side) {
            return createAndroidEmptyFile(named: name, in: side)
        }

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

    @discardableResult
    func renameItem(_ url: URL, to newName: String, on side: PaneSide) -> URL? {
        if url.scheme == AndroidFileURL.scheme {
            return renameAndroidItem(url, to: newName, on: side)
        }

        do {
            let renamed = try operationService.rename(url, to: newName)
            statusMessage = "Renamed to \(renamed.lastPathComponent)"
            refresh(side)
            setSelection([renamed], for: side)
            mergeRenamedItemIntoCurrentItems(renamed, replacing: url, on: side, source: "rename.commit")
            ensureRenamedItemAppears(renamed, on: side)
            logger.debug("selection", "selection.replaced", metadata: [
                "side": side.rawValue,
                "count": "1",
                "source": "rename.commit",
                "path": renamed.path
            ])
            return renamed
        } catch {
            reportOperationFailure("rename.failed", error: error)
            return nil
        }
    }

    private func ensureRenamedItemAppears(_ url: URL, on side: PaneSide) {
        guard !items(for: side).contains(where: { sameFileIdentity($0.url, url) }) else {
            logger.debug("navigation", "rename.refresh.target-present", metadata: [
                "side": side.rawValue,
                "path": url.path,
                "attempt": "0"
            ])
            return
        }

        logger.warning("navigation", "rename.refresh.target-missing", metadata: [
            "side": side.rawValue,
            "path": url.path,
            "attempt": "0",
            "itemCount": "\(items(for: side).count)"
        ])

        let delays: [TimeInterval] = [0.03, 0.10, 0.25, 0.50]
        for (index, delay) in delays.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self else { return }
                guard self.selection(on: side, contains: url) else {
                    self.logger.debug("navigation", "rename.refresh.retry-cancelled", metadata: [
                        "side": side.rawValue,
                        "path": url.path,
                        "attempt": "\(index + 1)",
                        "reason": "selection-changed"
                    ])
                    return
                }

                self.refresh(side)
                self.mergeRenamedItemIntoCurrentItems(url, replacing: nil, on: side, source: "rename.refresh.retry")
                self.setSelection([url], for: side)
                let containsTarget = self.items(for: side).contains(where: { self.sameFileIdentity($0.url, url) })
                self.logger.debug("navigation", "rename.refresh.retry", metadata: [
                    "side": side.rawValue,
                    "path": url.path,
                    "attempt": "\(index + 1)",
                    "delay": String(format: "%.2f", delay),
                    "containsTarget": "\(containsTarget)",
                    "itemCount": "\(self.items(for: side).count)"
                ])
            }
        }
    }

    private func mergeRenamedItemIntoCurrentItems(
        _ url: URL,
        replacing oldURL: URL?,
        on side: PaneSide,
        source: String
    ) {
        do {
            let item = try fileSystem.item(
                at: url,
                folderSizeCache: folderSizeCache,
                textEncodingCache: textEncodingCache,
                includeTextEncoding: uiLayoutPreferences.isEncodingColumnVisible
            )
            let rule = sortRuleStore.rule(for: flatViewRoot(for: side) ?? pane(for: side).selectedURL)
            let oldStandardizedURL = oldURL?.standardizedFileURL
            var nextItems = items(for: side).filter { existing in
                !sameFileIdentity(existing.url, item.url)
                    && oldStandardizedURL.map { !sameFileIdentity(existing.url, $0) } != false
            }
            nextItems.append(item)
            nextItems.sort { FileSystemService.sortItems($0, $1, rule: rule) }
            setItems(nextItems, for: side)
            logger.debug("navigation", "rename.items.merged", metadata: [
                "side": side.rawValue,
                "path": url.path,
                "source": source,
                "itemCount": "\(nextItems.count)",
                "index": "\(nextItems.firstIndex(where: { sameFileIdentity($0.url, item.url) }) ?? -1)",
                "itemURL": item.url.absoluteString,
                "targetURL": url.absoluteString
            ])
        } catch {
            logger.error("navigation", "rename.items.merge-failed", metadata: [
                "side": side.rawValue,
                "path": url.path,
                "source": source,
                "error": error.localizedDescription
            ])
        }
    }

    private func selection(on side: PaneSide, contains url: URL) -> Bool {
        pane(for: side).selectedItemURLs.contains { sameFileIdentity($0, url) }
    }

    private func sameFileIdentity(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }

    private func createAndroidFolder(in side: PaneSide) -> URL? {
        guard let parsed = AndroidFileURL.parse(pane(for: side).selectedURL) else { return nil }
        do {
            let path = try androidFileService.createDirectory(
                named: "New Folder",
                in: parsed.path,
                on: parsed.deviceSerial
            )
            let created = AndroidFileURL.url(deviceSerial: parsed.deviceSerial, path: path)
            statusMessage = "Created \(created.lastPathComponent)"
            refresh(side)
            setSelection([created], for: side)
            return created
        } catch {
            reportOperationFailure("android.folder.create.failed", error: error)
            return nil
        }
    }

    private func createAndroidEmptyFile(named name: String, in side: PaneSide) -> URL? {
        guard let parsed = AndroidFileURL.parse(pane(for: side).selectedURL) else { return nil }
        do {
            let path = try androidFileService.createEmptyFile(
                named: name,
                in: parsed.path,
                on: parsed.deviceSerial
            )
            let created = AndroidFileURL.url(deviceSerial: parsed.deviceSerial, path: path)
            statusMessage = "Created \(created.lastPathComponent)"
            refresh(side)
            setSelection([created], for: side)
            return created
        } catch {
            reportOperationFailure("android.file.create.failed", error: error)
            return nil
        }
    }

    private func renameAndroidItem(_ url: URL, to newName: String, on side: PaneSide) -> URL? {
        guard let parsed = AndroidFileURL.parse(url) else { return nil }
        do {
            let path = try androidFileService.renameRemote(parsed.path, to: newName, on: parsed.deviceSerial)
            let renamed = AndroidFileURL.url(deviceSerial: parsed.deviceSerial, path: path)
            statusMessage = "Renamed to \(newName)"
            refresh(side)
            setSelection([renamed], for: side)
            logger.debug("selection", "selection.replaced", metadata: [
                "side": side.rawValue,
                "count": "1",
                "source": "android.rename.commit",
                "path": renamed.path
            ])
            return renamed
        } catch {
            reportOperationFailure("android.rename.failed", error: error)
            return nil
        }
    }

    func selectedItems(on side: PaneSide) -> [FileItem] {
        let selected = pane(for: side).selectedItemURLs
        return items(for: side).filter { selected.contains($0.url) }
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

    func extractFilenamesFromContent(on side: PaneSide) {
        guard !isAndroidPane(side), !isInlineRenaming else { return }
        let items = selectedItems(on: side)
        guard !items.isEmpty else {
            statusMessage = "Select TXT files to rename"
            return
        }

        let plan = ContentTitleRenamePlanner().plan(for: items)
        guard !plan.operations.isEmpty else {
            statusMessage = "No extractable filenames found"
            logger.warning("content-title-rename", "no-operations", metadata: [
                "side": side.rawValue,
                "skipped": "\(plan.skipped.count)"
            ])
            return
        }

        do {
            let operations = plan.operations
            let renamedURLs = try operationService.batchRename(operations)
            refresh(side)
            setSelection(Set(renamedURLs), for: side)
            let changedCount = operations.filter { $0.sourceURL.standardizedFileURL != $0.destinationURL }.count
            statusMessage = plan.skipped.isEmpty
                ? "Extracted filenames for \(changedCount) item(s)"
                : "Extracted filenames for \(changedCount) item(s), skipped \(plan.skipped.count)"
            logger.info("content-title-rename", "applied", metadata: [
                "side": side.rawValue,
                "count": "\(changedCount)",
                "skipped": "\(plan.skipped.count)"
            ])
        } catch {
            reportOperationFailure("content-title-rename.failed", error: error)
        }
    }

    func mergeFiles(_ sources: [URL], named name: String, on side: PaneSide) {
        guard !isAndroidPane(side), !isInlineRenaming else { return }
        let mergeSources = mergeableFileURLs(sources, on: side)
        guard mergeSources.count >= 2 else {
            statusMessage = "Select at least two files to merge"
            return
        }

        do {
            let created = try operationService.mergeFiles(
                mergeSources,
                named: name,
                in: pane(for: side).selectedURL,
                trashSourcesAfterMerge: true
            )
            refresh(side)
            setSelection([created], for: side)
            requestPaneFocus(side, requestID: UUID().uuidString, source: "merge.completed")
            statusMessage = "Merged \(mergeSources.count) files into \(created.lastPathComponent) and moved originals to Trash"
            logger.info("file-operation", "merge.applied", metadata: [
                "side": side.rawValue,
                "count": "\(mergeSources.count)",
                "path": created.path
            ])
        } catch {
            reportOperationFailure("merge.failed", error: error)
        }
    }

    func splitFile(_ preview: TextFileSplitPreview, on side: PaneSide) {
        guard !isAndroidPane(side), !isInlineRenaming else { return }
        do {
            let created = try TextFileSplitService().split(preview, deleteOriginal: true)
            refresh(side)
            setSelection(Set(created), for: side)
            requestPaneFocus(side, requestID: UUID().uuidString, source: "split-file.completed")
            statusMessage = "Split \(preview.sourceURL.lastPathComponent) into \(created.count) file(s)"
            logger.info("file-operation", "split-file.completed", metadata: [
                "side": side.rawValue,
                "source": preview.sourceURL.path,
                "count": "\(created.count)"
            ])
        } catch {
            reportOperationFailure("split-file.failed", error: error)
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

    func syncSelection(from sourceSide: PaneSide) {
        performSelectionOperation(from: sourceSide, operation: .sync)
    }

    func trashSelection(
        from sourceSide: PaneSide,
        refreshPolicy: FileOperationRefreshPolicy = .refreshWhenFinished
    ) {
        if isAndroidPane(sourceSide) {
            deleteAndroidSelection(from: sourceSide)
            return
        }

        let sources = orderedSelection(pane(for: sourceSide).selectedItemURLs, on: sourceSide)
        guard !sources.isEmpty else { return }
        logger.info("file-operation", "trash.selection.requested", metadata: [
            "side": sourceSide.rawValue,
            "count": "\(sources.count)",
            "refreshPolicy": refreshPolicy.logValue,
            "similarReviewActive": "\(similarFileReviewActiveSides.contains(sourceSide))",
            "sources": sources.map(\.path).joined(separator: "|")
        ])
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
        enqueueFileOperation(.trash, sources: sources, destination: nil, refreshPolicy: refreshPolicy)
    }

    private func deleteAndroidSelection(from side: PaneSide) {
        let urls = orderedSelection(pane(for: side).selectedItemURLs, on: side)
        let remotePaths = urls.compactMap { AndroidFileURL.parse($0)?.path }
        guard let deviceSerial = androidDeviceSerial(for: side), !remotePaths.isEmpty else { return }
        let remoteByteSizes = androidSelectionByteSizes(for: urls, on: side)

        clearSelection(side)
        enqueueFileOperation(
            .trash,
            sources: urls,
            destination: nil,
            execution: .android(.remove(remoteURLs: urls, remotePaths: remotePaths, remoteByteSizes: remoteByteSizes, deviceSerial: deviceSerial))
        )
    }

    func trashActiveSelection() {
        let side = activePaneSide
        let isSimilarReviewActive = similarFileReviewActiveSides.contains(side)
        let selectedURLs = pane(for: side).selectedItemURLs
        if isSimilarReviewActive, !selectedURLs.isEmpty {
            similarFileDeletionMarkRequest = SimilarFileDeletionMarkRequest(side: side, urls: selectedURLs)
            logger.debug("similar-file-review", "visual-delete.requested.from-active-trash", metadata: [
                "side": side.rawValue,
                "count": "\(selectedURLs.count)"
            ])
        }
        trashSelection(
            from: side,
            refreshPolicy: FileOperationRefreshPolicy.trashPolicy(isSimilarFileReviewActive: isSimilarReviewActive)
        )
    }

    func emptyTrash() {
        guard !isInlineRenaming else { return }
        do {
            let summary = try operationService.trashContentsSummary()
            guard !summary.isEmpty else {
                statusMessage = "Trash is already empty"
                return
            }
            emptyTrashConfirmationRequest = EmptyTrashConfirmationRequest(summary: summary)
            statusMessage = "Confirm Empty Trash: \(summary.containedItemCount) item(s), \(ByteCountFormatter.string(fromByteCount: summary.totalByteCount, countStyle: .file))"
            logger.warning("file-operation", "trash.empty.confirmation.requested", metadata: [
                "topLevelItemCount": "\(summary.topLevelItemCount)",
                "containedItemCount": "\(summary.containedItemCount)",
                "totalByteCount": "\(summary.totalByteCount)"
            ])
        } catch {
            reportOperationFailure("trash.empty.preview.failed", error: error)
        }
    }

    func confirmEmptyTrash() {
        guard let request = emptyTrashConfirmationRequest else {
            logger.debug("file-operation", "trash.empty.confirm.ignored.no-request", metadata: [:])
            return
        }
        emptyTrashConfirmationRequest = nil
        logger.warning("file-operation", "trash.empty.confirmed", metadata: [
            "topLevelItemCount": "\(request.summary.topLevelItemCount)",
            "containedItemCount": "\(request.summary.containedItemCount)",
            "totalByteCount": "\(request.summary.totalByteCount)"
        ])
        do {
            let removedCount = try operationService.emptyTrash()
            refreshAll()
            statusMessage = "Emptied Trash: \(removedCount) item(s)"
        } catch {
            reportOperationFailure("trash.empty.failed", error: error)
        }
    }

    func cancelEmptyTrash() {
        guard let request = emptyTrashConfirmationRequest else { return }
        emptyTrashConfirmationRequest = nil
        statusMessage = "Empty Trash cancelled"
        logger.info("file-operation", "trash.empty.cancelled", metadata: [
            "topLevelItemCount": "\(request.summary.topLevelItemCount)",
            "containedItemCount": "\(request.summary.containedItemCount)",
            "totalByteCount": "\(request.summary.totalByteCount)"
        ])
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

    func convertSelectedTextEncodingToUTF8(on side: PaneSide) {
        guard !isInlineRenaming, !isTextEncodingConversionRunning else { return }
        let sources = orderedSelection(pane(for: side).selectedItemURLs, on: side)
        guard !sources.isEmpty else { return }

        activatePane(side)
        isTextEncodingConversionRunning = true
        statusMessage = "Analyzing text encoding for \(sources.count) item(s)..."
        logger.info("text-encoding", "selection.convert.requested", metadata: [
            "side": side.rawValue,
            "count": "\(sources.count)",
            "sources": sources.map(\.path).joined(separator: "|")
        ])

        let conversionLogger = logger
        let textEncodingCache = textEncodingCache
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let result = try TextEncodingConversionService(
                    logger: conversionLogger,
                    cache: textEncodingCache
                ).convertFilesToUTF8(sources) { completedCount, totalCount, fileResult in
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.isTextEncodingConversionRunning else { return }
                        self.statusMessage = self.textEncodingConversionProgress(
                            completedCount: completedCount,
                            totalCount: totalCount,
                            result: fileResult
                        )
                    }
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isTextEncodingConversionRunning = false
                    self.refresh(side)
                    let finalSelection = Set(result.results
                        .filter { $0.status != .skipped }
                        .map(\.finalURL))
                    if !finalSelection.isEmpty {
                        self.setSelection(finalSelection, for: side)
                    }
                    let problemReportURL = self.writeTextEncodingProblemReport(for: result)
                    self.statusMessage = self.textEncodingConversionSummary(result, problemReportURL: problemReportURL)
                    self.logger.info("text-encoding", "selection.convert.completed", metadata: [
                        "side": side.rawValue,
                        "converted": "\(result.convertedCount)",
                        "utf8": "\(result.alreadyUTF8Count)",
                        "cachedUTF8": "\(result.cachedUTF8Count)",
                        "unknownRenamed": "\(result.renamedUnknownCount)",
                        "skipped": "\(result.skippedCount)",
                        "failed": "\(result.failedCount)"
                    ])
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.isTextEncodingConversionRunning = false
                    self.reportOperationFailure("text-encoding.convert.failed", error: error)
                }
            }
        }
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
        guard !isAndroidPane(side) else {
            statusMessage = "Folder size calculation is local-only"
            return
        }

        let selected = pane(for: side).selectedItemURLs
        let folders = items(for: side).filter { selected.contains($0.url) && $0.isDirectoryLike }
        guard !folders.isEmpty else { return }

        let cache = folderSizeCache
        let folderURLs = folders.map(\.url)
        statusMessage = "Calculating folder size for \(folders.count) folder(s)..."

        DispatchQueue.global(qos: .userInitiated).async {
            let service = FileSystemService()
            var completed = 0
            var computed = 0
            var cached = 0
            var failures = 0

            for folderURL in folderURLs {
                do {
                    let result = try service.calculateFolderSize(at: folderURL, cache: cache, forceRecalculate: true)
                    let source: String
                    switch result {
                    case .cached:
                        source = "cache"
                        cached += 1
                    case .computed:
                        source = "computed"
                        computed += 1
                    }
                    completed += 1
                    let snapshot = (completed: completed, computed: computed, cached: cached, failures: failures)
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.logger.info("folder-size", "folder.size.resolved", metadata: [
                            "side": side.rawValue,
                            "path": folderURL.path,
                            "bytes": "\(result.size)",
                            "source": source
                        ])
                        self.refresh(side)
                        self.statusMessage = self.folderSizeProgressMessage(snapshot, total: folderURLs.count)
                    }
                } catch {
                    failures += 1
                    completed += 1
                    let snapshot = (completed: completed, computed: computed, cached: cached, failures: failures)
                    let errorDescription = error.localizedDescription
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.logger.error("folder-size", "folder.size.failed", metadata: [
                            "side": side.rawValue,
                            "path": folderURL.path,
                            "error": errorDescription
                        ])
                        self.statusMessage = self.folderSizeProgressMessage(snapshot, total: folderURLs.count)
                    }
                }
            }
        }
    }

    private func folderSizeProgressMessage(
        _ progress: (completed: Int, computed: Int, cached: Int, failures: Int),
        total: Int
    ) -> String {
        var parts = [
            "\(progress.completed)/\(total) done",
            "\(progress.computed) computed",
            "\(progress.cached) cached"
        ]
        if progress.failures > 0 {
            parts.append("\(progress.failures) failed")
        }
        return "Folder size: " + parts.joined(separator: ", ")
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
        if isAndroidPane(side) {
            pushLocalFilesToAndroid(sources, into: side, move: move)
            return
        }

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

        if performAndroidAwareSelectionOperation(sources: sources, from: sourceSide, operation: operation) {
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

    @discardableResult
    private func performAndroidAwareSelectionOperation(
        sources: [URL],
        from sourceSide: PaneSide,
        operation: QueuedFileOperationKind
    ) -> Bool {
        let destinationSide = opposite(sourceSide)
        let sourceIsAndroid = isAndroidPane(sourceSide)
        let destinationIsAndroid = isAndroidPane(destinationSide)
        guard sourceIsAndroid || destinationIsAndroid else { return false }

        switch (sourceIsAndroid, destinationIsAndroid) {
        case (false, true):
            guard let destination = AndroidFileURL.parse(pane(for: destinationSide).selectedURL) else { return true }
            clearSelection(sourceSide)
            enqueueFileOperation(
                operation,
                sources: sources,
                destination: pane(for: destinationSide).selectedURL,
                execution: .android(.push(
                    localURLs: sources,
                    remoteDirectory: destination.path,
                    deviceSerial: destination.deviceSerial,
                    removeLocalAfterCopy: operation == .move,
                    sync: operation == .sync
                ))
            )
        case (true, false):
            guard let sourceDevice = androidDeviceSerial(for: sourceSide) else { return true }
            let remotePaths = sources.compactMap { AndroidFileURL.parse($0)?.path }
            guard !remotePaths.isEmpty else { return true }
            let remoteByteSizes = androidSelectionByteSizes(for: sources, on: sourceSide)
            clearSelection(sourceSide)
            enqueueFileOperation(
                operation,
                sources: sources,
                destination: pane(for: destinationSide).selectedURL,
                execution: .android(.pull(
                    remoteURLs: sources,
                    remotePaths: remotePaths,
                    remoteByteSizes: remoteByteSizes,
                    localDirectory: pane(for: destinationSide).selectedURL,
                    deviceSerial: sourceDevice,
                    removeRemoteAfterCopy: operation == .move,
                    sync: operation == .sync
                ))
            )
        case (true, true):
            guard let sourceDevice = androidDeviceSerial(for: sourceSide),
                  let destination = AndroidFileURL.parse(pane(for: destinationSide).selectedURL) else { return true }
            guard sourceDevice == destination.deviceSerial else {
                reportOperationFailure("android.\(operation.rawValue).failed", error: AndroidPaneTransferError.differentDevices)
                return true
            }
            let remotePaths = sources.compactMap { AndroidFileURL.parse($0)?.path }
            guard !remotePaths.isEmpty else { return true }
            let remoteByteSizes = androidSelectionByteSizes(for: sources, on: sourceSide)
            clearSelection(sourceSide)
            enqueueFileOperation(
                operation,
                sources: sources,
                destination: pane(for: destinationSide).selectedURL,
                execution: .android(.transfer(
                    remoteURLs: sources,
                    remotePaths: remotePaths,
                    remoteByteSizes: remoteByteSizes,
                    remoteDirectory: destination.path,
                    deviceSerial: sourceDevice,
                    move: operation == .move,
                    sync: operation == .sync
                ))
            )
        case (false, false):
            return false
        }
        return true
    }

    private func androidSelectionByteSizes(for sources: [URL], on side: PaneSide) -> [Int64?] {
        let itemsByURL = Dictionary(uniqueKeysWithValues: items(for: side).map { ($0.url, $0) })
        return sources.map { source in
            guard let item = itemsByURL[source], item.kind == .file else { return nil }
            return item.size
        }
    }

    private func pushLocalFilesToAndroid(_ sources: [URL], into side: PaneSide, move: Bool, refresh: Bool = true) {
        guard let parsed = AndroidFileURL.parse(pane(for: side).selectedURL) else { return }
        enqueueFileOperation(
            move ? .move : .copy,
            sources: sources,
            destination: pane(for: side).selectedURL,
            execution: .android(.push(
                localURLs: sources,
                remoteDirectory: parsed.path,
                deviceSerial: parsed.deviceSerial,
                removeLocalAfterCopy: move,
                sync: false
            )),
            refreshPolicy: refresh ? .refreshWhenFinished : .deferSuccessfulRefresh
        )
    }

    private func enqueueFileOperation(
        _ kind: QueuedFileOperationKind,
        sources: [URL],
        destination: URL?,
        execution: QueuedFileOperationExecution = .local,
        refreshPolicy: FileOperationRefreshPolicy = .refreshWhenFinished
    ) {
        let id = UUID()
        let cancellation = FileOperationCancellation()
        let request = QueuedFileOperationRequest(
            id: id,
            kind: kind,
            sources: sources,
            destination: destination,
            execution: execution,
            cancellation: cancellation,
            refreshPolicy: refreshPolicy
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
        logger.info("file-operation", "operation.started", metadata: [
            "id": request.id.uuidString,
            "kind": request.kind.rawValue,
            "count": "\(request.sources.count)",
            "destination": request.destination?.path ?? "",
            "sources": request.sources.map(\.path).joined(separator: "|")
        ])
        recordFileOperationProgress(
            FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: 0,
                totalItems: 0,
                currentItem: request.sources.first,
                rootCompletedItems: 0,
                rootTotalItems: request.sources.count,
                elapsedSeconds: 0
            ),
            for: request.id
        )

        let id = request.id
        let kind = request.kind
        let sources = request.sources
        let destination = request.destination
        let execution = request.execution
        let cancellation = request.cancellation
        let refreshPolicy = request.refreshPolicy
        let conflictPreviews = destination.map {
            Self.fileConflictPreviews(for: sources, destinationDirectory: $0)
        } ?? []
        let androidFileService = androidFileService
        let operationLogger = logger
        let scanCache = operationScanCache

        Task.detached(priority: .userInitiated) { [weak self] in
            let service = FileOperationService(logger: operationLogger, operationScanCache: scanCache)
            var applyAllResolution: FileOperationConflictResolution?

            func resolveConflict(_ conflict: FileOperationConflict) -> FileOperationConflictResolution {
                if applyAllResolution == .largerWins {
                    return FileOperationService.largerWinsResolution(for: conflict)
                }
                if let applyAllResolution {
                    return applyAllResolution
                }
                let answer = self?.resolveConflictSynchronously(conflict, previews: conflictPreviews)
                    ?? FileConflictAnswer(resolution: .keepBoth, applyToAll: false)
                if answer.applyToAll {
                    applyAllResolution = answer.resolution
                }
                if answer.resolution == .largerWins {
                    return FileOperationService.largerWinsResolution(for: conflict)
                }
                return answer.resolution
            }

            do {
                switch execution {
                case .local:
                    switch kind {
                    case .copy:
                        guard let destination else { throw FileOperationError.invalidDestination }
                        try service.copy(
                            sources,
                            to: destination,
                            cancellation: cancellation,
                            progress: { progress in
                                Task { @MainActor [weak self] in
                                    self?.recordFileOperationProgress(progress, for: id)
                                }
                            },
                            conflictResolver: resolveConflict
                        )
                    case .sync:
                        guard let destination else { throw FileOperationError.invalidDestination }
                        try service.copy(
                            sources,
                            to: destination,
                            options: FileOperationOptions(syncMode: true),
                            cancellation: cancellation,
                            progress: { progress in
                                Task { @MainActor [weak self] in
                                    self?.recordFileOperationProgress(progress, for: id)
                                }
                            },
                            conflictResolver: resolveConflict
                        )
                    case .move:
                        guard let destination else { throw FileOperationError.invalidDestination }
                        try service.move(
                            sources,
                            to: destination,
                            cancellation: cancellation,
                            progress: { progress in
                                Task { @MainActor [weak self] in
                                    self?.recordFileOperationProgress(progress, for: id)
                                }
                            },
                            conflictResolver: resolveConflict
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
                case .android(let androidOperation):
                    try Self.performQueuedAndroidOperation(
                        androidOperation,
                        service: androidFileService,
                        cancellation: cancellation,
                        progress: { progress in
                            Task { @MainActor [weak self] in
                                self?.recordFileOperationProgress(progress, for: id)
                            }
                        }
                    )
                }

                Task { @MainActor [weak self] in
                    self?.finishFileOperation(
                        id,
                        status: .completed,
                        message: "\(kind.displayName) completed",
                        refreshPolicy: refreshPolicy
                    )
                }
            } catch FileOperationError.cancelled {
                Task { @MainActor [weak self] in
                    self?.finishFileOperation(
                        id,
                        status: .cancelled,
                        message: "Cancelled",
                        refreshPolicy: refreshPolicy
                    )
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.finishFileOperation(
                        id,
                        status: .failed,
                        message: error.localizedDescription,
                        refreshPolicy: refreshPolicy
                    )
                    self?.reportOperationFailure("\(kind.rawValue).failed", error: error)
                }
            }
        }
    }

    private nonisolated static func performQueuedAndroidOperation(
        _ operation: AndroidQueuedFileOperation,
        service: AndroidFileService,
        cancellation: FileOperationCancellation,
        progress: @escaping (FileOperationProgress) -> Void
    ) throws {
        let operationStart = Date()
        let itemURLs = operation.itemURLs
        let totalItems = itemURLs.count
        let itemByteSizes = Self.estimatedAndroidOperationByteSizes(operation, service: service)
        let totalBytes = itemByteSizes.allSatisfy { $0 != nil }
            ? itemByteSizes.compactMap { $0 }.reduce(0, +)
            : 0

        func throwIfCancelled() throws {
            if cancellation.isCancelled {
                throw FileOperationError.cancelled
            }
        }

        func completedBytes(for completedItems: Int, currentItemBytes: Int64 = 0) -> Int64 {
            guard totalBytes > 0 else { return 0 }
            let priorBytes = itemByteSizes
                .prefix(completedItems)
                .compactMap { $0 }
                .reduce(0, +)
            guard itemByteSizes.indices.contains(completedItems),
                  let expectedCurrentItemBytes = itemByteSizes[completedItems] else {
                return priorBytes
            }
            return priorBytes + min(max(currentItemBytes, 0), expectedCurrentItemBytes)
        }

        func report(completedItems: Int, currentItem: URL?, currentIndex: Int?, currentCompletedBytes: Int64 = 0) {
            progress(FileOperationProgress(
                completedBytes: completedBytes(for: completedItems, currentItemBytes: currentCompletedBytes),
                totalBytes: totalBytes,
                completedItems: completedItems,
                totalItems: totalItems,
                currentItem: currentItem,
                currentItemBytes: currentIndex.flatMap { itemByteSizes.indices.contains($0) ? itemByteSizes[$0] : nil },
                elapsedSeconds: Date().timeIntervalSince(operationStart)
            ))
        }

        switch operation {
        case .push(let localURLs, let remoteDirectory, let deviceSerial, let removeLocalAfterCopy, let sync):
            guard totalItems > 0 else { return }
            report(completedItems: 0, currentItem: itemURLs.first, currentIndex: 0)
            for (index, url) in localURLs.enumerated() {
                try throwIfCancelled()
                report(completedItems: index, currentItem: url, currentIndex: index)
                try service.push(localURLs: [url], to: remoteDirectory, on: deviceSerial, sync: sync, cancellation: cancellation)
                if removeLocalAfterCopy, FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
                report(completedItems: index + 1, currentItem: nextItem(after: index, in: localURLs), currentIndex: index + 1)
            }
        case .pull(let remoteURLs, let remotePaths, _, let localDirectory, let deviceSerial, let removeRemoteAfterCopy, let sync):
            if sync {
                let plan = try androidSyncPullPlan(
                    remotePaths: remotePaths,
                    deviceSerial: deviceSerial,
                    service: service,
                    cancellation: cancellation
                )
                var stats = AndroidSyncPullStats()

                func reportSyncProgress(
                    currentRemotePath: String?,
                    currentFileBytes: Int64?,
                    currentCopiedBytes: Int64 = 0
                ) {
                    progress(FileOperationProgress(
                        completedBytes: stats.completedBytes + min(max(currentCopiedBytes, 0), currentFileBytes ?? 0),
                        totalBytes: plan.totalBytes,
                        completedItems: stats.completedItems,
                        totalItems: plan.totalItems,
                        currentItem: currentRemotePath.map {
                            AndroidFileURL.url(deviceSerial: deviceSerial, path: $0)
                        },
                        currentItemBytes: currentFileBytes,
                        copiedItems: stats.copiedItems,
                        copiedBytes: stats.copiedBytes + min(max(currentCopiedBytes, 0), currentFileBytes ?? 0),
                        skippedItems: stats.skippedItems,
                        skippedBytes: stats.skippedBytes,
                        elapsedSeconds: Date().timeIntervalSince(operationStart)
                    ))
                }

                reportSyncProgress(
                    currentRemotePath: plan.roots.first?.remoteFiles.first?.path,
                    currentFileBytes: plan.roots.first?.remoteFiles.first?.size
                )

                for root in plan.roots {
                    for remoteFile in root.remoteFiles {
                        try throwIfCancelled()

                        let localFile = localFileURL(
                            forRemoteFile: remoteFile.path,
                            remoteRoot: root.remoteRoot,
                            rootName: root.rootName,
                            localDirectory: localDirectory
                        )

                        if localByteSize(at: localFile) == remoteFile.size {
                            stats.completedItems += 1
                            stats.completedBytes += remoteFile.size
                            stats.skippedItems += 1
                            stats.skippedBytes += remoteFile.size
                            service.logSyncDecision("file.skipped.same-size", remotePath: remoteFile.path, localPath: localFile.path, size: remoteFile.size)
                            reportSyncProgress(currentRemotePath: remoteFile.path, currentFileBytes: remoteFile.size)
                            continue
                        }

                        service.logSyncDecision("file.copying", remotePath: remoteFile.path, localPath: localFile.path, size: remoteFile.size)
                        reportSyncProgress(currentRemotePath: remoteFile.path, currentFileBytes: remoteFile.size)
                        let poller = AndroidPullProgressPoller(
                            targetURL: localFile,
                            expectedBytes: remoteFile.size,
                            interval: 1.0
                        ) { copiedFileBytes in
                            reportSyncProgress(
                                currentRemotePath: remoteFile.path,
                                currentFileBytes: remoteFile.size,
                                currentCopiedBytes: copiedFileBytes
                            )
                        }
                        poller.start()
                        defer { poller.stop() }
                        try service.pullFile(remotePath: remoteFile.path, to: localFile, on: deviceSerial, cancellation: cancellation)
                        stats.completedItems += 1
                        stats.completedBytes += remoteFile.size
                        stats.copiedItems += 1
                        stats.copiedBytes += remoteFile.size
                        service.logSyncDecision("file.copied", remotePath: remoteFile.path, localPath: localFile.path, size: remoteFile.size)
                        reportSyncProgress(currentRemotePath: remoteFile.path, currentFileBytes: remoteFile.size)
                    }
                }

                if removeRemoteAfterCopy {
                    for path in remotePaths {
                        try service.removeRemote([path], on: deviceSerial)
                    }
                }
                reportSyncProgress(currentRemotePath: nil, currentFileBytes: nil)
            } else {
                guard totalItems > 0 else { return }
                report(completedItems: 0, currentItem: itemURLs.first, currentIndex: 0)
                for (index, pair) in zip(remoteURLs, remotePaths).enumerated() {
                    try throwIfCancelled()
                    let (url, path) = pair
                    report(completedItems: index, currentItem: url, currentIndex: index)
                    let targetURL = localDirectory
                        .appendingPathComponent((AndroidFileURL.normalizedPath(path) as NSString).lastPathComponent)
                        .standardizedFileURL
                    let poller = AndroidPullProgressPoller(
                        targetURL: targetURL,
                        expectedBytes: itemByteSizes.indices.contains(index) ? itemByteSizes[index] : nil,
                        interval: 1.0
                    ) { copiedBytes in
                        report(
                            completedItems: index,
                            currentItem: url,
                            currentIndex: index,
                            currentCompletedBytes: copiedBytes
                        )
                    }
                    poller.start()
                    defer { poller.stop() }
                    try service.pull(remotePaths: [path], to: localDirectory, on: deviceSerial, cancellation: cancellation)
                    if removeRemoteAfterCopy {
                        try service.removeRemote([path], on: deviceSerial)
                    }
                    report(completedItems: index + 1, currentItem: nextItem(after: index, in: remoteURLs), currentIndex: index + 1)
                }
            }
        case .transfer(let remoteURLs, let remotePaths, _, let remoteDirectory, let deviceSerial, let move, let sync):
            guard totalItems > 0 else { return }
            report(completedItems: 0, currentItem: itemURLs.first, currentIndex: 0)
            for (index, pair) in zip(remoteURLs, remotePaths).enumerated() {
                try throwIfCancelled()
                let (url, path) = pair
                report(completedItems: index, currentItem: url, currentIndex: index)
                if move {
                    try service.moveRemote([path], to: remoteDirectory, on: deviceSerial)
                } else if sync {
                    try service.copyRemote([path], to: remoteDirectory, on: deviceSerial)
                } else {
                    try service.copyRemote([path], to: remoteDirectory, on: deviceSerial)
                }
                report(completedItems: index + 1, currentItem: nextItem(after: index, in: remoteURLs), currentIndex: index + 1)
            }
        case .remove(let remoteURLs, let remotePaths, _, let deviceSerial):
            guard totalItems > 0 else { return }
            report(completedItems: 0, currentItem: itemURLs.first, currentIndex: 0)
            for (index, pair) in zip(remoteURLs, remotePaths).enumerated() {
                try throwIfCancelled()
                let (url, path) = pair
                report(completedItems: index, currentItem: url, currentIndex: index)
                try service.removeRemote([path], on: deviceSerial)
                report(completedItems: index + 1, currentItem: nextItem(after: index, in: remoteURLs), currentIndex: index + 1)
            }
        }
    }

    private nonisolated static func estimatedAndroidOperationByteSizes(
        _ operation: AndroidQueuedFileOperation,
        service: AndroidFileService
    ) -> [Int64?] {
        let maximumRemoteItemsForByteEstimates = 32

        switch operation {
        case .push(let localURLs, _, _, _, _):
            return localURLs.map { localByteSize(at: $0) }
        case .pull(_, let remotePaths, let remoteByteSizes, _, let deviceSerial, _, _):
            if remoteByteSizes.count == remotePaths.count {
                return remoteByteSizes
            }
            guard remotePaths.count <= maximumRemoteItemsForByteEstimates else {
                return Array(repeating: nil, count: remotePaths.count)
            }
            return remotePaths.map { service.estimatedByteSize(of: $0, on: deviceSerial) }
        case .transfer(_, let remotePaths, let remoteByteSizes, _, let deviceSerial, _, _):
            if remoteByteSizes.count == remotePaths.count {
                return remoteByteSizes
            }
            guard remotePaths.count <= maximumRemoteItemsForByteEstimates else {
                return Array(repeating: nil, count: remotePaths.count)
            }
            return remotePaths.map { service.estimatedByteSize(of: $0, on: deviceSerial) }
        case .remove(_, let remotePaths, let remoteByteSizes, let deviceSerial):
            if remoteByteSizes.count == remotePaths.count {
                return remoteByteSizes
            }
            guard remotePaths.count <= maximumRemoteItemsForByteEstimates else {
                return Array(repeating: nil, count: remotePaths.count)
            }
            return remotePaths.map { service.estimatedByteSize(of: $0, on: deviceSerial) }
        }
    }

    private nonisolated static func androidSyncPullPlan(
        remotePaths: [String],
        deviceSerial: String,
        service: AndroidFileService,
        cancellation: FileOperationCancellation
    ) throws -> AndroidSyncPullPlan {
        let roots = try remotePaths.map { remotePath in
            if cancellation.isCancelled {
                throw FileOperationError.cancelled
            }
            let remoteRoot = AndroidFileURL.normalizedPath(remotePath)
            return AndroidSyncPullRootPlan(
                remoteRoot: remoteRoot,
                rootName: (remoteRoot as NSString).lastPathComponent,
                remoteFiles: try service.regularFiles(under: remoteRoot, on: deviceSerial, cancellation: cancellation)
            )
        }
        return AndroidSyncPullPlan(roots: roots)
    }

    private nonisolated static func localFileURL(
        forRemoteFile remoteFile: String,
        remoteRoot: String,
        rootName: String,
        localDirectory: URL
    ) -> URL {
        let normalizedRemoteFile = AndroidFileURL.normalizedPath(remoteFile)
        if normalizedRemoteFile == remoteRoot {
            return localDirectory.appendingPathComponent(rootName).standardizedFileURL
        }

        let rootPrefix = remoteRoot == "/" ? "/" : remoteRoot + "/"
        let relativePath = normalizedRemoteFile.hasPrefix(rootPrefix)
            ? String(normalizedRemoteFile.dropFirst(rootPrefix.count))
            : (normalizedRemoteFile as NSString).lastPathComponent
        return localDirectory
            .appendingPathComponent(rootName, isDirectory: true)
            .appendingPathComponent(relativePath)
            .standardizedFileURL
    }

    private struct AndroidSyncPullPlan {
        let roots: [AndroidSyncPullRootPlan]
        let totalItems: Int
        let totalBytes: Int64

        init(roots: [AndroidSyncPullRootPlan]) {
            self.roots = roots
            totalItems = roots.reduce(0) { $0 + $1.remoteFiles.count }
            totalBytes = roots.reduce(Int64(0)) { rootTotal, root in
                rootTotal + root.remoteFiles.reduce(Int64(0)) { $0 + $1.size }
            }
        }
    }

    private struct AndroidSyncPullRootPlan {
        let remoteRoot: String
        let rootName: String
        let remoteFiles: [AndroidRemoteFile]
    }

    private struct AndroidSyncPullStats {
        var completedItems = 0
        var completedBytes: Int64 = 0
        var copiedItems = 0
        var copiedBytes: Int64 = 0
        var skippedItems = 0
        var skippedBytes: Int64 = 0
    }

    private nonisolated static func localByteSize(at url: URL) -> Int64? {
        let fileManager = FileManager.default
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey]) else {
            return nil
        }
        if values.isRegularFile == true {
            return Int64(values.fileSize ?? 0)
        }
        guard values.isDirectory == true && values.isSymbolicLink != true else {
            return 0
        }

        var total: Int64 = 0
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else {
            return nil
        }
        for case let child as URL in enumerator {
            guard let childValues = try? child.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  childValues.isRegularFile == true else {
                continue
            }
            total += Int64(childValues.fileSize ?? 0)
        }
        return total
    }

    private final class AndroidPullProgressPoller: @unchecked Sendable {
        private let targetURL: URL
        private let expectedBytes: Int64?
        private let interval: TimeInterval
        private let onProgress: (Int64) -> Void
        private let lock = NSLock()
        private var isRunning = false

        init(
            targetURL: URL,
            expectedBytes: Int64?,
            interval: TimeInterval,
            onProgress: @escaping (Int64) -> Void
        ) {
            self.targetURL = targetURL
            self.expectedBytes = expectedBytes
            self.interval = interval
            self.onProgress = onProgress
        }

        func start() {
            lock.lock()
            guard !isRunning else {
                lock.unlock()
                return
            }
            isRunning = true
            lock.unlock()

            DispatchQueue.global(qos: .utility).async { [weak self] in
                self?.run()
            }
        }

        func stop() {
            lock.lock()
            isRunning = false
            lock.unlock()
        }

        private func run() {
            while running {
                publishCurrentSize()
                Thread.sleep(forTimeInterval: interval)
            }
            publishCurrentSize()
        }

        private var running: Bool {
            lock.lock()
            defer { lock.unlock() }
            return isRunning
        }

        private func publishCurrentSize() {
            guard var size = DualFinderViewModel.localByteSize(at: targetURL) else { return }
            if let expectedBytes {
                size = min(size, expectedBytes)
            }
            onProgress(size)
        }
    }

    private nonisolated static func nextItem(after index: Int, in urls: [URL]) -> URL? {
        let nextIndex = index + 1
        guard urls.indices.contains(nextIndex) else { return nil }
        return urls[nextIndex]
    }

    private func recordFileOperationProgress(_ progress: FileOperationProgress, for id: UUID) {
        updateQueuedOperation(id) {
            $0.progress = progress
            if let currentItem = progress.currentItem {
                $0.message = currentItem.lastPathComponent
            }
        }
        if let operation = fileOperationQueue.first(where: { $0.id == id }) {
            statusMessage = "\(operation.title): \(operation.message)"
        }
    }

    private func finishFileOperation(
        _ id: UUID,
        status: QueuedFileOperationStatus,
        message: String,
        refreshPolicy: FileOperationRefreshPolicy
    ) {
        updateQueuedOperation(id) {
            $0.status = status
            $0.message = message
            $0.finishedAt = Date()
        }
        pendingOperationRequests.removeAll { $0.id == id }
        isProcessingFileOperations = false
        let shouldRefresh = refreshPolicy.shouldRefresh(status: status)
        logger.info("file-operation", "operation.finished", metadata: [
            "id": id.uuidString,
            "status": status.rawValue,
            "refreshPolicy": refreshPolicy.logValue,
            "willRefresh": "\(shouldRefresh)",
            "message": message
        ])
        if shouldRefresh {
            refreshAll()
        }
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
        guard !operationInvolvesAndroid(operation) else { return false }
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
        if operationInvolvesAndroid(operation) {
            return "Recovery unavailable: retry Android transfers from the pane after checking the device connection."
        }
        let existingSourceCount = operation.sources.filter { FileManager.default.fileExists(atPath: $0.path) }.count
        if existingSourceCount == 0 {
            return "Recovery unavailable: the source item no longer exists."
        }
        if operation.kind != .trash, operation.destination == nil {
            return "Recovery unavailable: the destination folder is missing from the operation record."
        }
        return "Fix the reported issue, then retry with \(existingSourceCount) available source item(s)."
    }

    private func operationInvolvesAndroid(_ operation: QueuedFileOperation) -> Bool {
        operation.sources.contains { $0.scheme == AndroidFileURL.scheme }
            || operation.destination?.scheme == AndroidFileURL.scheme
    }

    private func updateQueuedOperation(_ id: UUID, mutate: (inout QueuedFileOperation) -> Void) {
        guard let index = fileOperationQueue.firstIndex(where: { $0.id == id }) else { return }
        mutate(&fileOperationQueue[index])
    }

    private nonisolated func resolveConflictSynchronously(
        _ conflict: FileOperationConflict,
        previews: [FileConflictPreview]
    ) -> FileConflictAnswer {
        let box = FileConflictAnswerBox()
        Task { @MainActor [weak self] in
            self?.activeConflictAnswerBox = box
            self?.fileConflictDialogRequest = FileConflictDialogRequest(
                source: conflict.source,
                destination: conflict.destination,
                conflicts: Self.conflictPreviews(including: conflict, in: previews)
            )
        }
        return box.wait()
    }

    nonisolated static func fileConflictPreviews(
        for sources: [URL],
        destinationDirectory: URL,
        fileManager: FileManager = .default
    ) -> [FileConflictPreview] {
        sources.compactMap { source in
            let destination = destinationDirectory.appendingPathComponent(source.lastPathComponent)
            guard fileManager.fileExists(atPath: destination.path) else { return nil }
            return FileConflictPreview(
                source: source,
                destination: destination,
                sourceSize: regularFileSize(at: source),
                destinationSize: regularFileSize(at: destination),
                largerWinsResolution: FileOperationService.largerWinsResolution(
                    for: FileOperationConflict(source: source, destination: destination)
                )
            )
        }
    }

    private nonisolated static func conflictPreviews(
        including conflict: FileOperationConflict,
        in previews: [FileConflictPreview]
    ) -> [FileConflictPreview] {
        let current = FileConflictPreview(
            source: conflict.source,
            destination: conflict.destination,
            sourceSize: regularFileSize(at: conflict.source),
            destinationSize: regularFileSize(at: conflict.destination),
            largerWinsResolution: FileOperationService.largerWinsResolution(for: conflict)
        )
        guard !previews.contains(where: { $0.id == current.id }) else { return previews }
        return [current] + previews
    }

    private nonisolated static func regularFileSize(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values?.isRegularFile == true else { return nil }
        return values?.fileSize.map(Int64.init)
    }

    private func flatViewRootCandidate(on side: PaneSide) -> URL? {
        let selection = pane(for: side).selectedItemURLs
        if selection.isEmpty {
            return pane(for: side).selectedURL.standardizedFileURL
        }

        guard selection.count == 1,
              let selected = items(for: side).first(where: { selection.contains($0.url) }) else {
            statusMessage = "Flat view needs no selection or one selected folder"
            logger.debug("flat-view", "toggle.ignored.invalid-selection", metadata: [
                "side": side.rawValue,
                "count": "\(selection.count)"
            ])
            return nil
        }

        if selected.kind == .folder {
            return selected.url.standardizedFileURL
        }

        return selected.url.deletingLastPathComponent().standardizedFileURL
    }

    private func enterFlatView(root: URL, on side: PaneSide) {
        setFlatViewRoot(root, for: side)
        setFlatViewReturnSelection(pane(for: side).selectedItemURLs, for: side)
        clearSelection(side)
        refreshFlatView(root: root, on: side)
        logger.info("flat-view", "entered", metadata: [
            "side": side.rawValue,
            "root": root.path
        ])
    }

    private func exitFlatView(on side: PaneSide) {
        let root = flatViewRoot(for: side)
        let returnSelection = flatViewReturnSelection(for: side)
        clearFlatViewState(on: side)
        refresh(side)
        let validReturnSelection = returnSelection.intersection(Set(items(for: side).map(\.url)))
        setSelection(validReturnSelection, for: side)
        statusMessage = "Flat view off"
        logger.info("flat-view", "exited", metadata: [
            "side": side.rawValue,
            "root": root?.path ?? ""
        ])
    }

    private func refreshFlatView(root: URL, on side: PaneSide) {
        do {
            let rule = sortRuleStore.rule(for: root)
            let nextItems = try fileSystem.recursiveFileContents(
                of: root,
                includeHidden: showHiddenFiles,
                sortRule: rule,
                folderSizeCache: folderSizeCache,
                textEncodingCache: textEncodingCache,
                includeTextEncoding: uiLayoutPreferences.isEncodingColumnVisible
            )
            setItems(nextItems, for: side)
            startTextEncodingScanIfNeeded(for: side, items: nextItems)
            statusMessage = "Flat: \(root.path) - \(nextItems.count) file(s)"
            logger.info("flat-view", "refreshed", metadata: [
                "side": side.rawValue,
                "root": root.path,
                "count": "\(nextItems.count)",
                "showHidden": "\(showHiddenFiles)",
                "sort": "\(rule.field.rawValue).\(rule.direction.rawValue)"
            ])
        } catch {
            clearFlatViewState(on: side)
            statusMessage = "Failed to read \(root.path): \(error.localizedDescription)"
            logger.error("flat-view", "refresh.failed", metadata: [
                "side": side.rawValue,
                "root": root.path,
                "error": error.localizedDescription
            ])
            handlePossiblePermissionFailure(error, path: root.path)
            refresh(side)
        }
    }

    private func setItems(_ items: [FileItem], for side: PaneSide) {
        if side == .left {
            leftItems = items
        } else {
            rightItems = items
        }
    }

    private func startTextEncodingScanIfNeeded(for side: PaneSide, items: [FileItem]) {
        cancelTextEncodingScan(for: side)
        guard uiLayoutPreferences.isEncodingColumnVisible else { return }

        let pendingItems = items.filter { $0.kind == .file && $0.textEncoding == nil }
        guard !pendingItems.isEmpty else { return }

        let cancellation = TextEncodingScanCancellation()
        textEncodingScanCancellations[side] = cancellation
        let cache = textEncodingCache
        let logger = logger

        DispatchQueue.global(qos: .utility).async {
            let service = TextEncodingConversionService(logger: logger, cache: cache)
            for item in pendingItems {
                guard !cancellation.isCancelled else { return }
                let encoding = (try? service.detectFileEncoding(item.url)) ?? "unknown"
                guard !cancellation.isCancelled else { return }

                DispatchQueue.main.async { [weak self] in
                    guard let self,
                          self.textEncodingScanCancellations[side] === cancellation,
                          self.uiLayoutPreferences.isEncodingColumnVisible else {
                        return
                    }
                    self.updateTextEncoding(encoding, for: item.url, on: side)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.textEncodingScanCancellations[side] === cancellation else {
                    return
                }
                self.textEncodingScanCancellations[side] = nil
            }
        }
    }

    private func updateTextEncoding(_ encoding: String, for url: URL, on side: PaneSide) {
        if side == .left {
            updateTextEncoding(encoding, for: url, in: &leftItems)
        } else {
            updateTextEncoding(encoding, for: url, in: &rightItems)
        }
    }

    private func updateTextEncoding(_ encoding: String, for url: URL, in items: inout [FileItem]) {
        guard let index = items.firstIndex(where: { $0.url == url }),
              items[index].textEncoding == nil else {
            return
        }
        items[index] = items[index].withTextEncoding(encoding)
    }

    private func cancelTextEncodingScans() {
        for cancellation in textEncodingScanCancellations.values {
            cancellation.cancel()
        }
        textEncodingScanCancellations.removeAll()
    }

    private func cancelTextEncodingScan(for side: PaneSide) {
        textEncodingScanCancellations[side]?.cancel()
        textEncodingScanCancellations[side] = nil
    }

    private func setFlatViewRoot(_ root: URL?, for side: PaneSide) {
        if side == .left {
            leftFlatViewRootURL = root
        } else {
            rightFlatViewRootURL = root
        }
    }

    private func clearFlatViewRoot(on side: PaneSide) {
        setFlatViewRoot(nil, for: side)
    }

    private func flatViewReturnSelection(for side: PaneSide) -> Set<URL> {
        side == .left ? leftFlatViewReturnSelection : rightFlatViewReturnSelection
    }

    private func setFlatViewReturnSelection(_ selection: Set<URL>, for side: PaneSide) {
        if side == .left {
            leftFlatViewReturnSelection = selection
        } else {
            rightFlatViewReturnSelection = selection
        }
    }

    private func clearFlatViewState(on side: PaneSide) {
        clearFlatViewRoot(on: side)
        setFlatViewReturnSelection([], for: side)
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

    private func selectionLogMetadata(
        _ selection: Set<URL>,
        side: PaneSide,
        source: String? = nil
    ) -> [String: String] {
        var metadata = [
            "side": side.rawValue,
            "count": "\(selection.count)"
        ]
        if let source {
            metadata["source"] = source
        }
        guard selection.count <= 20 else {
            metadata["samplePaths"] = selection.lazy.prefix(5).map(\.path).joined(separator: "|")
            metadata["pathsTruncated"] = "true"
            return metadata
        }
        metadata["paths"] = selection.map(\.path).sorted().joined(separator: "|")
        return metadata
    }

    private func setSelection(_ selection: Set<URL>, for side: PaneSide) {
        if side == .left {
            leftPane.selectedItemURLs = selection
        } else {
            rightPane.selectedItemURLs = selection
        }
    }

    private func persistPaneSession() {
        paneSessionStore.save(
            left: paneForSessionPersistence(.left),
            right: paneForSessionPersistence(.right)
        )
    }

    private func paneForSessionPersistence(_ side: PaneSide) -> PaneState {
        guard isAndroidPane(side) else { return pane(for: side) }
        return PaneState(
            side: side,
            initialURL: localPaneReturnURLs[side] ?? FileManager.default.homeDirectoryForCurrentUser
        )
    }

    private func reconcilePaneModeAfterHistoryNavigation(to url: URL, on side: PaneSide) {
        if let parsed = AndroidFileURL.parse(url) {
            androidPaneDevices[side] = parsed.deviceSerial
        } else {
            androidPaneDevices[side] = nil
        }
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

    private func mergeableFileURLs(in selection: Set<URL>, on side: PaneSide) -> [URL] {
        guard selection.count >= 2 else { return [] }
        return mergeableFileURLs(orderedSelection(selection, on: side), on: side)
    }

    private func mergeableFileURLs(_ urls: [URL], on side: PaneSide) -> [URL] {
        guard urls.count >= 2, Set(urls).count == urls.count else { return [] }
        let itemByURL = Dictionary(uniqueKeysWithValues: items(for: side).map { ($0.url, $0) })
        guard urls.allSatisfy({ itemByURL[$0]?.kind == .file }) else {
            return []
        }
        return urls
    }

    func canSplitFile(in selection: Set<URL>, on side: PaneSide) -> Bool {
        canSplitFile(orderedSelection(selection, on: side), on: side)
    }

    private func canSplitFile(_ urls: [URL], on side: PaneSide) -> Bool {
        guard !isAndroidPane(side), !isInlineRenaming else { return false }
        let itemByURL = Dictionary(uniqueKeysWithValues: items(for: side).map { ($0.url, $0) })
        guard urls.count == 1, let source = urls.first, itemByURL[source]?.kind == .file else {
            return false
        }
        return TextFileSplitService.canSplit(urls)
    }

    private func fileURLsFromPasteboard() -> [URL] {
        FilePasteboardReader.fileURLs()
    }

    private func setupPasteboardObservation() {
        NotificationCenter.default.addObserver(
            forName: .pasteboardChanged,
            object: NSPasteboard.general,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pasteboardRevision &+= 1
            }
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

    private func textEncodingConversionSummary(
        _ result: TextEncodingBatchConversionResult,
        problemReportURL: URL? = nil
    ) -> String {
        let parts = [
            result.convertedCount > 0 ? "\(result.convertedCount) converted to UTF-8" : nil,
            result.alreadyUTF8Count > 0 ? alreadyUTF8Summary(for: result) : nil,
            result.renamedUnknownCount > 0 ? "\(result.renamedUnknownCount) moved to unknown_encode" : nil,
            result.skippedCount > 0 ? "\(result.skippedCount) skipped" : nil,
            result.failedCount > 0 ? "\(result.failedCount) failed" : nil
        ].compactMap { $0 }

        var summary = parts.isEmpty ? "No text encoding changes" : "Encoding check complete: \(parts.joined(separator: ", "))"
        if let problemReportURL {
            summary += ". Problem list: \(problemReportURL.lastPathComponent)"
        }
        return summary
    }

    private func textEncodingConversionProgress(
        completedCount: Int,
        totalCount: Int,
        result: TextEncodingConversionResult
    ) -> String {
        if result.usedCache {
            return "Encoding \(completedCount)/\(totalCount): skipping cached UTF-8 files (\(completedCount) checked)"
        }
        let action = switch result.status {
        case .alreadyUTF8:
            "already UTF-8"
        case .converted:
            "converted to UTF-8"
        case .renamedUnknown:
            "moved to unknown_encode"
        case .skipped:
            "skipped"
        case .failed:
            "failed"
        }
        return "Encoding \(completedCount)/\(totalCount): \(result.finalURL.lastPathComponent) \(action)"
    }

    private func alreadyUTF8Summary(for result: TextEncodingBatchConversionResult) -> String {
        guard result.cachedUTF8Count > 0 else {
            return "\(result.alreadyUTF8Count) already UTF-8"
        }
        return "\(result.alreadyUTF8Count) already UTF-8 (\(result.cachedUTF8Count) cached)"
    }

    private func writeTextEncodingProblemReport(for result: TextEncodingBatchConversionResult) -> URL? {
        let problemResults = result.problemResults
        guard !problemResults.isEmpty, let appLogger = logger as? AppLogger else {
            return nil
        }

        let timestamp = Self.textEncodingReportTimestampFormatter.string(from: Date())
        let reportURL = appLogger.logDirectory.appendingPathComponent("text-encoding-problems-\(timestamp).txt")
        var lines = [
            "DualFinder text encoding problem files",
            "Generated: \(timestamp)",
            "Unknown: \(result.renamedUnknownCount)",
            "Failed: \(result.failedCount)",
            ""
        ]

        for result in problemResults {
            lines.append("Status:   \(textEncodingReportStatus(for: result.status))")
            lines.append("Original: \(result.originalURL.path)")
            lines.append("Current:  \(result.finalURL.path)")
            if let diagnostic = result.diagnostic {
                lines.append("Reason:   \(diagnostic)")
            }
            lines.append("")
        }

        do {
            try FileManager.default.createDirectory(at: appLogger.logDirectory, withIntermediateDirectories: true)
            try lines.joined(separator: "\n").write(to: reportURL, atomically: true, encoding: .utf8)
            logger.warning("text-encoding", "selection.convert.problem-report", metadata: [
                "path": reportURL.path,
                "unknown": "\(result.renamedUnknownCount)",
                "failed": "\(result.failedCount)"
            ])
            return reportURL
        } catch {
            logger.error("text-encoding", "selection.convert.problem-report.failed", metadata: [
                "error": String(describing: error)
            ])
            return nil
        }
    }

    private func textEncodingReportStatus(for status: TextEncodingConversionStatus) -> String {
        switch status {
        case .alreadyUTF8:
            "already UTF-8"
        case .converted:
            "converted"
        case .renamedUnknown:
            "moved to unknown_encode"
        case .skipped:
            "skipped"
        case .failed:
            "failed"
        }
    }

    private static let textEncodingReportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()

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
