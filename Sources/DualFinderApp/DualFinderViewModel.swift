import AppKit
import Foundation
import SwiftUI
import DualFinderCore

@MainActor
final class DualFinderViewModel: ObservableObject {
    @Published var leftPane: PaneState
    @Published var rightPane: PaneState
    @Published private(set) var leftItems: [FileItem] = []
    @Published private(set) var rightItems: [FileItem] = []
    @Published var statusMessage: String = ""
    @Published var diskAccessPrompt: DiskAccessPrompt?
    @Published private(set) var activePaneSide: PaneSide = .left
    @Published var isInlineRenaming = false
    @Published var showHiddenFiles = false {
        didSet { refreshAll() }
    }

    private let fileSystem: FileSystemService
    private let operationService: FileOperationService
    private let sortRuleStore: FolderSortRuleStore
    private let paneSessionStore: PaneSessionStore
    private let folderSizeCache: FolderSizeCache
    private let permissionGuide: PrivacyPermissionGuide
    private let quickLookPreviewService: QuickLookPreviewService
    private let logger: AppLogging
    private var didAutoOpenDiskAccessSettings = false

    init(
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: FileSystemService = FileSystemService(),
        sortRuleStore: FolderSortRuleStore = FolderSortRuleStore(),
        paneSessionStore: PaneSessionStore = PaneSessionStore(),
        folderSizeCache: FolderSizeCache = FolderSizeCache(),
        permissionGuide: PrivacyPermissionGuide = PrivacyPermissionGuide(),
        quickLookPreviewService: QuickLookPreviewService = QuickLookPreviewService(),
        logger: AppLogging
    ) {
        self.fileSystem = fileSystem
        self.sortRuleStore = sortRuleStore
        self.paneSessionStore = paneSessionStore
        self.folderSizeCache = folderSizeCache
        self.permissionGuide = permissionGuide
        self.quickLookPreviewService = quickLookPreviewService
        self.logger = logger
        let restoredPanes = paneSessionStore.load(fallbackURL: initialURL)
        leftPane = restoredPanes.left
        rightPane = restoredPanes.right
        operationService = FileOperationService(logger: logger)
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
        !pane(for: activePaneSide).selectedItemURLs.isEmpty
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
        persistPaneSession()
        logger.info("navigation", "directory.changed", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
        refresh(side)
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

    func closeSelectedTab(on side: PaneSide) {
        let tabID = pane(for: side).selectedTabID
        let didClose = mutatePane(side) { $0.closeTab(id: tabID) }
        if didClose {
            persistPaneSession()
            logger.info("tab", "tab.closed", metadata: ["side": side.rawValue, "tab": tabID.uuidString])
            refresh(side)
        } else {
            logger.debug("tab", "tab.close.ignored", metadata: ["side": side.rawValue, "tab": tabID.uuidString])
        }
    }

    func selectTab(_ id: UUID, on side: PaneSide) {
        guard pane(for: side).tabs.contains(where: { $0.id == id }) else { return }
        mutatePane(side) { pane in
            pane.selectedTabID = id
            pane.selectedItemURLs.removeAll()
        }
        persistPaneSession()
        logger.info("tab", "tab.selected", metadata: ["side": side.rawValue, "tab": id.uuidString])
        refresh(side)
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

    func copySelection(from sourceSide: PaneSide) {
        performSelectionOperation(from: sourceSide, operationName: "copy") { sources, destination in
            try operationService.copy(sources, to: destination)
        }
    }

    func moveSelection(from sourceSide: PaneSide) {
        performSelectionOperation(from: sourceSide, operationName: "move") { sources, destination in
            try operationService.move(sources, to: destination)
        }
    }

    func trashSelection(from sourceSide: PaneSide) {
        let sources = Array(pane(for: sourceSide).selectedItemURLs)
        guard !sources.isEmpty else { return }
        do {
            try operationService.trash(sources)
            clearSelection(sourceSide)
            refreshAll()
            statusMessage = "Moved \(sources.count) item(s) to Trash"
        } catch {
            reportOperationFailure("trash.failed", error: error)
        }
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

    private func performSelectionOperation(
        from sourceSide: PaneSide,
        operationName: String,
        body: ([URL], URL) throws -> Void
    ) {
        let sources = Array(pane(for: sourceSide).selectedItemURLs)
        guard !sources.isEmpty else { return }
        let destination = pane(for: opposite(sourceSide)).selectedURL
        do {
            try body(sources, destination)
            clearSelection(sourceSide)
            refreshAll()
            statusMessage = "\(operationName.capitalized) completed: \(sources.count) item(s)"
        } catch {
            reportOperationFailure("\(operationName).failed", error: error)
        }
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

    private func orderedSelection(_ selection: Set<URL>, on side: PaneSide) -> [URL] {
        let itemURLs = items(for: side).map(\.url)
        let ordered = itemURLs.filter { selection.contains($0) }
        return ordered.isEmpty ? Array(selection).sorted { $0.path < $1.path } : ordered
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
