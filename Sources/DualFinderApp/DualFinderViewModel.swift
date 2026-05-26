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
    @Published var showHiddenFiles = false {
        didSet { refreshAll() }
    }

    private let fileSystem: FileSystemService
    private let operationService: FileOperationService
    private let logger: AppLogging

    init(
        initialURL: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileSystem: FileSystemService = FileSystemService(),
        logger: AppLogging
    ) {
        self.fileSystem = fileSystem
        self.logger = logger
        leftPane = PaneState(side: .left, initialURL: initialURL)
        rightPane = PaneState(side: .right, initialURL: initialURL)
        operationService = FileOperationService(logger: logger)
        logger.info("view-model", "initialized", metadata: ["initialURL": initialURL.path])
    }

    func items(for side: PaneSide) -> [FileItem] {
        side == .left ? leftItems : rightItems
    }

    func pane(for side: PaneSide) -> PaneState {
        side == .left ? leftPane : rightPane
    }

    func bindingForSelection(side: PaneSide) -> Binding<Set<URL>> {
        Binding(
            get: { self.pane(for: side).selectedItemURLs },
            set: { newValue in
                self.setSelection(newValue, for: side)
                self.logger.debug("selection", "selection.changed", metadata: [
                    "side": side.rawValue,
                    "count": "\(newValue.count)"
                ])
            }
        )
    }

    func clickItem(_ url: URL, on side: PaneSide) {
        mutatePane(side) { $0.selectSingleItem(url) }
        logger.debug("selection", "item.clicked", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
    }

    func refreshAll() {
        refresh(.left)
        refresh(.right)
    }

    func refresh(_ side: PaneSide) {
        let currentURL = pane(for: side).selectedURL
        do {
            let nextItems = try fileSystem.contents(of: currentURL, includeHidden: showHiddenFiles)
            setItems(nextItems, for: side)
            statusMessage = "\(currentURL.path) - \(nextItems.count) items"
            logger.info("navigation", "directory.refreshed", metadata: [
                "side": side.rawValue,
                "path": currentURL.path,
                "count": "\(nextItems.count)",
                "showHidden": "\(showHiddenFiles)"
            ])
        } catch {
            statusMessage = "Failed to read \(currentURL.path): \(error.localizedDescription)"
            logger.error("navigation", "directory.refresh.failed", metadata: [
                "side": side.rawValue,
                "path": currentURL.path,
                "error": error.localizedDescription
            ])
        }
    }

    func navigate(_ side: PaneSide, to url: URL) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            openInFinder(url)
            return
        }
        mutatePane(side) { $0.navigateSelectedTab(to: url) }
        logger.info("navigation", "directory.changed", metadata: [
            "side": side.rawValue,
            "path": url.path
        ])
        refresh(side)
    }

    func navigateUp(_ side: PaneSide) {
        guard let parent = fileSystem.parent(of: pane(for: side).selectedURL) else { return }
        navigate(side, to: parent)
    }

    func navigateHome(_ side: PaneSide) {
        navigate(side, to: FileManager.default.homeDirectoryForCurrentUser)
    }

    func addTab(on side: PaneSide) {
        let id = mutatePane(side) { pane in
            pane.addTab(url: pane.selectedURL)
        }
        logger.info("tab", "tab.added", metadata: ["side": side.rawValue, "tab": id.uuidString])
        refresh(side)
    }

    func closeSelectedTab(on side: PaneSide) {
        let tabID = pane(for: side).selectedTabID
        let didClose = mutatePane(side) { $0.closeTab(id: tabID) }
        if didClose {
            logger.info("tab", "tab.closed", metadata: ["side": side.rawValue, "tab": tabID.uuidString])
            refresh(side)
        } else {
            logger.debug("tab", "tab.close.ignored", metadata: ["side": side.rawValue, "tab": tabID.uuidString])
        }
    }

    func selectTab(_ id: UUID, on side: PaneSide) {
        if side == .left {
            leftPane.selectedTabID = id
            leftPane.selectedItemURLs.removeAll()
        } else {
            rightPane.selectedTabID = id
            rightPane.selectedItemURLs.removeAll()
        }
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

    func createFolder(in side: PaneSide) {
        let directory = pane(for: side).selectedURL
        do {
            let created = try operationService.createFolder(named: "New Folder", in: directory)
            statusMessage = "Created \(created.lastPathComponent)"
            refresh(side)
        } catch {
            reportOperationFailure("folder.create.failed", error: error)
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

    func openLogFolder() {
        if let appLogger = logger as? AppLogger {
            NSWorkspace.shared.open(appLogger.logDirectory)
        }
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
    }
}
