import AppKit
import SwiftUI
import DualFinderCore
import UniformTypeIdentifiers

@MainActor
private enum FileListMetrics {
    static let horizontalPadding: CGFloat = 16
    static let iconColumnWidth: CGFloat = 20
    static let iconColumnSpacing: CGFloat = 8

    static var verticalScrollerGutter: CGFloat {
        NSScroller.scrollerWidth(for: .regular, scrollerStyle: NSScroller.preferredScrollerStyle)
    }
}

private let similarFileGroupColors: [Color] = [
    .teal,
    .indigo,
    .orange,
    .green,
    .pink,
    .cyan
]

private struct SimilarFileGroupMarker {
    let color: Color
    let isCurrent: Bool
}

struct FilePaneView: View {
    let side: PaneSide
    @ObservedObject var model: DualFinderViewModel
    @ObservedObject var terminalModel: EmbeddedTerminalPaneModel
    let onToggleTerminalMaximized: (PaneSide) -> Void
    @State private var renamingURL: URL?
    @State private var pendingRenameURL: URL?
    @State private var pendingRevealURL: URL?
    @State private var pendingNewFolderMoveSources: [URL]?
    @State private var renameText = ""
    @State private var isEditingPath = false
    @State private var pathText = ""
    @State private var isFileSearchPresented = false
    @State private var fileSearchQuery = ""
    @State private var fileSearchAppliedQuery = ""
    @State private var fileSearchDebounceWorkItem: DispatchWorkItem?
    @State private var isDropTargeted = false
    @State private var terminalResizeStartHeight: CGFloat?
    @State private var terminalResizeAccumulatedDelta: CGFloat = 0
    @State private var terminalResizePreviewHeight: CGFloat?
    @State private var isSimilarFileNavigatorEnabled = false
    @State private var similarFileGroupIndex = 0
    @State private var similarFileGroups: [SimilarFileNameGroup] = []
    @State private var similarReviewVisibleItems: [FileItem] = []
    @State private var similarFileGroupMarkersByURL: [URL: SimilarFileGroupMarker] = [:]
    @State private var similarFileGroupIndexByURL: [URL: Int] = [:]
    @State private var handledSimilarFileGroupIDs: Set<String> = []
    @State private var visuallyDeletedSimilarFileURLs: Set<URL> = []
    @State private var fileListKeyboardAnchorURL: URL?
    @State private var toolbarVolumeEntries: [MountedVolumeLocation] = []
    @FocusState private var isFileListFocused: Bool
    @FocusState private var isPathFieldFocused: Bool
    @FocusState private var isFileSearchFocused: Bool
    @State private var freeSpaceCapacity: Int64?

    var body: some View {
        VStack(spacing: 0) {
            if !terminalModel.isMaximized {
                paneHeader
                tabStrip
                fileList
            }
            terminalPanel
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.pathEditRequest) { _, request in
            guard request?.side == side else { return }
            beginPathEditing()
        }
        .onChange(of: model.fileSearchRequest) { _, request in
            guard request?.side == side else { return }
            beginFileSearch()
        }
        .onChange(of: model.inlineRenameRequest) { _, request in
            guard let request, request.side == side else { return }
            model.inlineRenameRequest = nil
            beginRenaming(request.url)
        }
        .onChange(of: model.similarFileDeletionMarkRequest) { _, request in
            guard let request, request.side == side else { return }
            markSimilarFilesVisuallyDeleted(request.urls, source: "active-trash-shortcut")
        }
        .onChange(of: model.paneFocusRequest) { _, request in
            guard let request, request.side == side else { return }
            model.logPaneFocusEvent("file-list.focus-request.observed", metadata: [
                "requestID": request.requestID,
                "side": side.rawValue,
                "source": request.source,
                "revealPath": request.revealURL?.path ?? ""
            ])
            restoreFileListFocus(requestID: request.requestID, reason: request.source, revealURL: request.revealURL)
        }
        .onChange(of: model.pane(for: side).selectedURL) { _, url in
            if !isEditingPath {
                pathText = model.isAndroidPane(side)
                    ? (AndroidFileURL.parse(url)?.path ?? "/sdcard")
                    : url.path
            }
            resetSimilarFileNavigator()
            dismissFileSearch(restoreFocus: false)
        }
        .task(id: model.pane(for: side).selectedURL) {
            refreshFreeSpace()
        }
        .onAppear(perform: refreshToolbarVolumeEntries)
        .onAppear {
            model.refreshAndroidDevicesForToolbar()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didMountNotification)) { _ in
            refreshToolbarVolumeEntries()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didUnmountNotification)) { _ in
            refreshToolbarVolumeEntries()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didRenameVolumeNotification)) { _ in
            refreshToolbarVolumeEntries()
        }
    }

    private func refreshFreeSpace() {
        guard !model.isAndroidPane(side) else {
            freeSpaceCapacity = nil
            return
        }
        let url = model.pane(for: side).selectedURL
        freeSpaceCapacity = (try? FileSystemService().availableCapacity(at: url)) ?? nil
    }

    private var paneHeader: some View {
        let pane = model.pane(for: side)

        return HStack(spacing: 6) {
            IconButton(systemName: "chevron.left", help: "Go back") {
                model.navigateBack(side)
            }
            .disabled(!pane.canNavigateSelectedTabBack)
            IconButton(systemName: "chevron.right", help: "Go forward") {
                model.navigateForward(side)
            }
            .disabled(!pane.canNavigateSelectedTabForward)
            IconButton(systemName: "chevron.up", help: "Go to parent folder") {
                model.navigateUp(side)
            }
            IconButton(systemName: "house", help: "Go home") {
                model.navigateHome(side)
            }
            IconButton(systemName: "folder.badge.plus", help: "Choose folder") {
                model.chooseFolder(for: side)
            }
            androidViewMenu
            toolbarVolumeButtons
            pathControl
            Button {
                model.setEncodingColumnVisible(!model.isEncodingColumnVisible)
            } label: {
                Image(systemName: "textformat")
                    .frame(width: 22, height: 22)
                    .foregroundStyle(model.isEncodingColumnVisible ? Color.accentColor : Color.primary)
            }
            .buttonStyle(.borderless)
            .help(model.isEncodingColumnVisible ? "Hide encoding column" : "Show encoding column")
            .accessibilityLabel(model.isEncodingColumnVisible ? "Hide encoding column" : "Show encoding column")
            IconButton(systemName: "plus.square.on.square", help: "New tab") {
                model.addTab(on: side)
            }
            IconButton(systemName: "xmark.square", help: "Close tab") {
                model.closeSelectedTab(on: side)
            }
            IconButton(
                systemName: terminalModel.isExpanded ? "terminal.fill" : "terminal",
                help: terminalModel.isExpanded ? "Collapse embedded terminal" : "Show embedded terminal"
            ) {
                terminalModel.toggle(currentDirectory: terminalDirectory)
            }
            .disabled(model.isAndroidPane(side))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var toolbarVolumeButtons: some View {
        HStack(spacing: 4) {
            ForEach(toolbarVolumeEntries) { entry in
                Button {
                    model.navigate(side, to: entry.url)
                } label: {
                    Image(systemName: entry.iconName)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(isCurrentDirectory(entry.url) ? Color.accentColor : Color.primary)
                }
                .buttonStyle(.borderless)
                .help(entry.displayName)
                .accessibilityLabel("Open volume \(entry.displayName)")
                .contextMenu {
                    Button("Unmount \(entry.displayName)", role: .destructive) {
                        model.unmountVolume(entry.url)
                    }
                }
            }
        }
    }

    private func refreshToolbarVolumeEntries() {
        toolbarVolumeEntries = MountedVolumeLocations.current()
    }

    private func isCurrentDirectory(_ url: URL) -> Bool {
        model.pane(for: side).selectedURL.standardizedFileURL == url.standardizedFileURL
    }

    private var androidViewMenu: some View {
        Menu {
            if model.isAndroidPane(side) {
                Button("Local Files") {
                    model.switchPaneToLocal(side)
                }

                Divider()
            }

            Button("Refresh Android Devices") {
                model.refreshAndroidDevices()
            }

            Divider()

            let connectedDevices = model.androidDevices.filter { $0.state == .device }
            if connectedDevices.isEmpty {
                Text("No Android devices")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(connectedDevices) { device in
                    Button(androidDeviceTitle(device)) {
                        model.switchPaneToAndroid(side, deviceSerial: device.serial)
                    }
                }
            }
        } label: {
            Image(systemName: model.isAndroidPane(side) ? "iphone.gen3.radiowaves.left.and.right" : "iphone.gen3")
                .frame(width: 22, height: 22)
                .foregroundStyle(model.isAndroidPane(side) ? Color.accentColor : Color.primary)
        }
        .menuStyle(.borderlessButton)
        .help(model.isAndroidPane(side) ? "Android view" : "Switch to Android view")
        .accessibilityLabel(model.isAndroidPane(side) ? "Android view" : "Switch to Android view")
    }

    private func androidDeviceTitle(_ device: AndroidDevice) -> String {
        let label = device.model?.replacingOccurrences(of: "_", with: " ") ?? device.serial
        if device.state == .device {
            return label == device.serial ? label : "\(label) (\(device.serial))"
        }
        return "\(label) - \(androidStateTitle(device.state))"
    }

    private func androidStateTitle(_ state: AndroidDeviceState) -> String {
        switch state {
        case .device:
            return "connected"
        case .unauthorized:
            return "unauthorized"
        case .offline:
            return "offline"
        case .recovery:
            return "recovery"
        case .sideload:
            return "sideload"
        case .unknown(let value):
            return value
        }
    }

    @ViewBuilder
    private var pathControl: some View {
        if isEditingPath {
            TextField("Folder path", text: $pathText)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .focused($isPathFieldFocused)
                .onSubmit(commitPathEditing)
                .onKeyPress(.escape, phases: .down) { _ in
                    cancelPathEditing()
                    return .handled
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    isPathFieldFocused = true
                }
        } else {
            Text(model.displayPath(for: side))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginPathEditing()
                }
        }
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.pane(for: side).tabs) { tab in
                    Button {
                        model.selectTab(tab.id, on: side)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(tabTitle(for: tab.url))
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tab.id == model.pane(for: side).selectedTabID ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(tabHelp(for: tab.url))
                    .contextMenu {
                        pathAndTerminalContextMenuItems(for: Set([tab.url]), selectTabID: tab.id)
                        favoriteContextMenuItems(for: Set([tab.url]))
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private func tabTitle(for url: URL) -> String {
        if let android = AndroidFileURL.parse(url) {
            let name = android.path == "/" ? "/" : (android.path as NSString).lastPathComponent
            return name.isEmpty ? android.deviceSerial : name
        }
        return url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent
    }

    private func tabHelp(for url: URL) -> String {
        if let android = AndroidFileURL.parse(url) {
            return "\(android.deviceSerial):\(android.path)"
        }
        return url.path
    }

    @ViewBuilder
    private func finderStyleContextMenuItems(for selection: Set<URL>) -> some View {
        let ordered = model.orderedContextMenuURLs(selection, on: side)

        if model.canCreateFolderWithSelection(selection) {
            Button(newFolderWithSelectionTitle(selection.count)) {
                beginNewFolderWithSelection(ordered)
            }
        }

        if model.canMergeFiles(in: selection, on: side) {
            Button("Merge Files...") {
                model.requestMergeFilesDialog(on: side, urls: ordered)
            }
        }

        if model.canSplitFile(in: selection, on: side) {
            Button("Split File...") {
                model.requestSplitFileDialog(on: side, urls: ordered)
            }
        }

        if model.allSelectedItemsAreDirectories(in: selection, on: side) {
            Button(openInNewTabsTitle(selection.count)) {
                model.openSelectionInNewTabs(on: side, folderURLs: ordered)
            }
        }

        if !ordered.isEmpty {
            Button("Share...") {
                model.shareItems(ordered, on: side)
            }
        }
    }

    private func newFolderWithSelectionTitle(_ count: Int) -> String {
        "New Folder with Selection (\(count) \(count == 1 ? "Item" : "Items"))"
    }

    private func openInNewTabsTitle(_ count: Int) -> String {
        count == 1 ? "Open in New Tab" : "Open in New Tabs"
    }

    private func beginNewFolderWithSelection(_ sources: [URL]) {
        guard let created = model.createFolder(in: side) else { return }
        pendingNewFolderMoveSources = sources
        queueRename(created)
    }

    @ViewBuilder
    private func listContextMenuItems() -> some View {
        let selection = model.pane(for: side).selectedItemURLs

        if model.isAndroidPane(side) {
            Button("Copy Path") {
                model.copyAbsolutePaths(selection, on: side)
            }
        } else {
            finderStyleContextMenuItems(for: selection)
            Divider()
            pathAndTerminalContextMenuItems(for: selection)
            archiveContextMenuItems(for: selection)
            favoriteContextMenuItems(for: selection)
            Divider()
            Button("Convert Text Encoding to UTF-8") {
                model.convertSelectedTextEncodingToUTF8(on: side)
            }
            Button("Extract Filename from Content") {
                model.extractFilenamesFromContent(on: side)
            }
            Button("Batch Rename...") {
                model.requestBatchRenameDialog(on: side)
            }
        }
        Button("Copy to Other Pane") {
            model.copySelection(from: side)
        }
        Button("Move to Other Pane") {
            model.moveSelection(from: side)
        }
        Button("Sync to Other Pane") {
            model.syncSelection(from: side)
        }
        Button(model.isAndroidPane(side) ? "Delete" : "Move to Trash", role: .destructive) {
            trashSelectionFromPane(selectionHint: selection)
        }
    }

    @ViewBuilder
    private func pathAndTerminalContextMenuItems(for urls: Set<URL>, selectTabID: UUID? = nil) -> some View {
        Button("Copy Absolute Path") {
            if let selectTabID {
                model.selectTab(selectTabID, on: side)
            }
            model.copyAbsolutePaths(urls, on: side)
        }
        if !model.isAndroidPane(side) {
            Button("Open in Ghostty or Terminal") {
                if let selectTabID {
                    model.selectTab(selectTabID, on: side)
                }
                model.openInTerminal(urls, on: side)
            }
        }
    }

    @ViewBuilder
    private func favoriteContextMenuItems(for selection: Set<URL>) -> some View {
        let newFavorites = model.selectedDirectoryURLs(in: selection, on: side)
            .filter { !model.isFolderFavorite($0) }

        if newFavorites.count == 1, let folder = newFavorites.first {
            Button("Add to Favorite") {
                model.addFolderToFavorites(folder)
            }
        } else if newFavorites.count > 1 {
            Button("Add \(newFavorites.count) Folders to Favorites") {
                for folder in newFavorites {
                    model.addFolderToFavorites(folder)
                }
            }
        }
    }

    @ViewBuilder
    private func archiveContextMenuItems(for selection: Set<URL>) -> some View {
        let ordered = model.orderedContextMenuURLs(selection, on: side)
        if ArchiveService.canCompress(ordered) {
            Button("Compress to ZIP") {
                model.compressSelectionToZip(on: side)
            }
        }

        let archives = ArchiveService.extractableArchives(from: ordered)
        if !archives.isEmpty {
            Button("Extract Here") {
                model.extractArchiveSelection(on: side, mode: .currentDirectory)
            }
            if archives.count == 1, let archive = archives.first {
                let folderName = model.extractionSubfolderLabel(for: archive)
                Button("Extract to \"\(folderName)\"") {
                    model.extractArchiveSelection(on: side, mode: .namedSubfolder)
                }
            } else {
                Button("Extract to Subfolder(s)") {
                    model.extractArchiveSelection(on: side, mode: .namedSubfolder)
                }
            }
        }
    }

    private var fileList: some View {
        let visibleFileItems = visibleItems
        let selectionSnapshot = FileSelectionSnapshot(selection: model.pane(for: side).selectedItemURLs)

        return VStack(spacing: 0) {
            sortHeader
            ZStack(alignment: .topTrailing) {
                ScrollViewReader { scrollProxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleFileItems) { item in
                                FileRow(
                                    item: item,
                                    displayName: displayName(for: item),
                                    columnWidths: model.columnWidths(for: side),
                                    showsEncoding: model.isEncodingColumnVisible,
                                    isRenaming: renamingURL == item.url,
                                    isSelected: selectionSnapshot.contains(item.url),
                                    isActivePane: model.activePaneSide == side,
                                    isVisuallyDeleted: isSimilarFileVisuallyDeleted(item.url),
                                    renameText: $renameText,
                                    commitRename: commitRename,
                                    cancelRename: cancelRename
                                )
                                    .equatable()
                                    .id(item.url)
                                    .background(similarFileRowBackground(for: item))
                                    .contentShape(Rectangle())
                                    .overlay {
                                        if renamingURL != item.url {
                                            RowMouseHandler(
                                                mouseDown: { modifierFlags in
                                                    selectItemFromRowMouseDown(
                                                        item.url,
                                                        modifierFlags: modifierFlags
                                                    )
                                                },
                                                mouseUp: { modifierFlags in
                                                    selectItemFromRowMouseUp(
                                                        item.url,
                                                        modifierFlags: modifierFlags
                                                    )
                                                },
                                                doubleClick: {
                                                    activateItem(item.url)
                                                },
                                                dragURLsProvider: {
                                                    dragURLs(startingWith: item.url)
                                                },
                                                onDragStarted: { urls in
                                                    model.logDragDropEvent("drag.started", metadata: [
                                                        "side": side.rawValue,
                                                        "count": "\(urls.count)",
                                                        "paths": urls.map(\.path).joined(separator: "|")
                                                    ])
                                                }
                                            )
                                        }
                                    }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                    .id(isSimilarFileNavigatorEnabled ? "similar-review" : "normal-file-list")
                    .focusable()
                    .focused($isFileListFocused)
                    .onChange(of: isFileListFocused) { _, isFocused in
                        model.logPaneFocusEvent("file-list.focus-state.changed", metadata: [
                            "side": side.rawValue,
                            "focused": "\(isFocused)"
                        ])
                    }
                    .onKeyPress(.escape, phases: .down) { _ in
                        guard renamingURL == nil else { return .ignored }
                        if isFileSearchPresented {
                            dismissFileSearch()
                            return .handled
                        }
                        if model.isFlatViewActive(on: side) {
                            model.toggleFlatView(on: side)
                            return .handled
                        }
                        return .ignored
                    }
                    .onKeyPress(KeyEquivalent("b"), phases: .down) { keyPress in
                        guard isControlOnly(keyPress.modifiers),
                              renamingURL == nil,
                              !isFileSearchPresented else {
                            return .ignored
                        }

                        model.toggleFlatView(on: side)
                        return .handled
                    }
                    .onKeyPress(KeyEquivalent("e"), phases: .down) { keyPress in
                        guard isFileSearchPresented,
                              isControlOnly(keyPress.modifiers),
                              renamingURL == nil else {
                            return .ignored
                        }

                        focusFileSearchInput(selectAll: false)
                        return .handled
                    }
                    .onKeyPress(.return, phases: .down) { keyPress in
                        guard keyPress.modifiers.isEmpty else { return .ignored }
                        return beginRenamingSelectedItem() ? .handled : .ignored
                    }
                    .onKeyPress(KeyEquivalent("o"), phases: .down) { keyPress in
                        guard keyPress.modifiers.contains(.command) else { return .ignored }
                        model.openSelectionWithDefaultApp(on: side)
                        return .handled
                    }
                    .onKeyPress(KeyEquivalent("c"), phases: .down) { keyPress in
                        guard keyPress.modifiers.contains(.command), renamingURL == nil else { return .ignored }
                        if keyPress.modifiers.contains(.option) {
                            guard !keyPress.modifiers.contains(.shift), !keyPress.modifiers.contains(.control) else { return .ignored }
                            model.copyAbsolutePaths(model.pane(for: side).selectedItemURLs, on: side)
                            return .handled
                        }
                        guard !keyPress.modifiers.contains(.shift), !keyPress.modifiers.contains(.control) else { return .ignored }
                        let requestID = logFileClipboardShortcut("copy", modifiers: "command")
                        model.copySelectionToFileClipboard(on: side, requestID: requestID)
                        return .handled
                    }
                    .onKeyPress(KeyEquivalent("v"), phases: .down) { keyPress in
                        guard keyPress.modifiers.contains(.command), renamingURL == nil else { return .ignored }
                        guard !keyPress.modifiers.contains(.shift), !keyPress.modifiers.contains(.control) else { return .ignored }
                        if keyPress.modifiers.contains(.option) {
                            let requestID = logFileClipboardShortcut("paste.move", modifiers: "command+option")
                            model.pasteFileClipboard(into: side, operation: .move, requestID: requestID)
                            return .handled
                        }

                        let requestID = logFileClipboardShortcut("paste.copy", modifiers: "command")
                        model.pasteFileClipboard(into: side, operation: .copy, requestID: requestID)
                        return .handled
                    }
                    .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { keyPress in
                        guard keyPress.modifiers.contains(.command), renamingURL == nil else { return .ignored }
                        if keyPress.modifiers.contains(.shift) {
                            model.emptyTrash()
                        } else {
                            trashSelectionFromPane()
                        }
                        return .handled
                    }
                    .onKeyPress(.space, phases: .down) { keyPress in
                        guard renamingURL == nil else { return .ignored }
                        if keyPress.modifiers.contains(.control) {
                            model.calculateSelectedFolderSizes(on: side)
                            return .handled
                        }
                        guard keyPress.modifiers.isEmpty else { return .ignored }
                        model.previewSelection(on: side)
                        return .handled
                    }
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { keyPress in
                        guard keyPress.modifiers.contains(.command) else { return .ignored }
                        switch keyPress.key {
                        case .upArrow:
                            model.navigateUp(side)
                            return .handled
                        case .downArrow:
                            model.navigateIntoSelectedDirectory(side)
                            return .handled
                        default:
                            return .ignored
                        }
                    }
                    .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { keyPress in
                        guard keyPress.modifiers.isEmpty,
                              renamingURL == nil,
                              !isFileSearchPresented else {
                            return .ignored
                        }

                        if isSimilarFileNavigatorEnabled {
                            moveSimilarFileSelection(keyPress.key == .upArrow ? -1 : 1)
                        } else {
                            moveFileListSelection(keyPress.key == .upArrow ? -1 : 1)
                        }
                        return .handled
                    }
                    .background {
                        LocalKeyDownMonitor(
                            isEnabled: isFileListFocused,
                            handle: handleFileListKeyDown
                        )
                        .frame(width: 0, height: 0)
                    }
                    .contextMenu {
                        listContextMenuItems()
                    }
                    .safeAreaInset(edge: .bottom) {
                        HStack(spacing: 8) {
                            IconButton(systemName: "folder.badge.plus", help: "Create folder") {
                                if let created = model.createFolder(in: side) {
                                    queueRename(created)
                                }
                            }
                            IconButton(systemName: "doc.badge.plus", help: "Create TXT file") {
                                if let created = model.createEmptyFile(named: "New File.txt", in: side) {
                                    queueRename(created)
                                }
                            }
                            IconButton(systemName: "doc.text", help: "Create Markdown file") {
                                if let created = model.createEmptyFile(named: "New File.md", in: side) {
                                    queueRename(created)
                                }
                            }
                            IconButton(systemName: "trash", help: "Move selection to Trash") {
                                trashSelectionFromPane()
                            }
                            IconButton(systemName: "arrow.clockwise", help: "Refresh pane") {
                                model.refresh(side)
                            }
                            IconButton(systemName: "ruler", help: "Calculate selected folder size (Ctrl-Space)") {
                                model.calculateSelectedFolderSizes(on: side)
                            }
                            .disabled(model.isAndroidPane(side))
                            similarFileNavigatorControls(scrollProxy: scrollProxy)
                            Spacer()
                            footerStats
                        }
                        .padding(8)
                        .background(.bar)
                    }
                    .onChange(of: pendingRevealURL) { _, _ in
                        revealPendingItemIfReady(with: scrollProxy)
                    }
                    .onChange(of: model.items(for: side)) { _, _ in
                        reconcileVisuallyDeletedSimilarFiles()
                        revealPendingItemIfReady(with: scrollProxy)
                        synchronizeFileSearchSelection()
                        synchronizeSimilarFileNavigator(with: scrollProxy)
                    }
                    .onChange(of: fileSearchQuery) { _, _ in
                        scheduleFileSearchSynchronization()
                    }
                    .onChange(of: isFileSearchPresented) { _, _ in
                        synchronizeFileSearchSelection()
                    }
                    .onDrop(of: [.fileURL], delegate: FilePaneDropDelegate(
                        side: side, model: model, isDropTargeted: $isDropTargeted
                    ))
                    .overlay {
                        if isDropTargeted {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor, lineWidth: 2)
                                .padding(2)
                        }
                    }

                }

                if isFileSearchPresented {
                    fileSearchOverlay
                        .padding(.top, 6)
                        .padding(.trailing, 88)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onChange(of: model.items(for: side)) { _, _ in
            beginPendingRenameIfReady()
        }
        .onChange(of: model.pane(for: side).selectedItemURLs) { _, selection in
            guard let renamingURL, !selection.contains(renamingURL) else { return }
            clearRenameState()
        }
    }

    @ViewBuilder
    private var terminalPanel: some View {
        if terminalModel.isExpanded {
            ZStack(alignment: .top) {
                VStack(spacing: 0) {
                    if !terminalModel.isMaximized {
                        LayoutResizeHandle(
                            axis: .horizontal,
                            length: nil,
                            onDrag: { delta in
                                beginTerminalResizeIfNeeded()
                                terminalResizeAccumulatedDelta += delta
                                let nextHeight = (terminalResizeStartHeight ?? terminalModel.height)
                                    + terminalResizeAccumulatedDelta
                                terminalResizePreviewHeight = EmbeddedTerminalPaneModel.clampedHeight(nextHeight)
                            },
                            onDragEnded: {
                                if let terminalResizePreviewHeight {
                                    terminalModel.resize(to: terminalResizePreviewHeight)
                                }
                                resetTerminalResize()
                            }
                        )
                    }
                    EmbeddedTerminalPanel(
                        side: side,
                        paneModel: terminalModel,
                        currentDirectory: terminalDirectory,
                        openExternal: { directory in
                            model.openInTerminal(Set([directory]), on: side)
                        },
                        toggleMaximized: {
                            onToggleTerminalMaximized(side)
                        }
                    )
                    .frame(height: terminalModel.isMaximized ? nil : terminalModel.height)
                    .frame(maxHeight: terminalModel.isMaximized ? .infinity : nil)
                }
                if let terminalResizePreviewHeight, !terminalModel.isMaximized {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(height: 1)
                        .offset(y: terminalModel.height - terminalResizePreviewHeight)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func beginTerminalResizeIfNeeded() {
        guard terminalResizeStartHeight == nil else { return }
        terminalResizeStartHeight = terminalModel.height
        terminalResizeAccumulatedDelta = 0
    }

    private func resetTerminalResize() {
        terminalResizeStartHeight = nil
        terminalResizeAccumulatedDelta = 0
        terminalResizePreviewHeight = nil
    }

    private var terminalDirectory: URL {
        guard !model.isAndroidPane(side) else {
            return FileManager.default.homeDirectoryForCurrentUser
        }
        let url = model.pane(for: side).selectedURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url.standardizedFileURL
        }
        return url.deletingLastPathComponent().standardizedFileURL
    }

    private var visibleItems: [FileItem] {
        if isSimilarFileNavigatorEnabled {
            return similarReviewVisibleItems
        }

        let allItems = model.items(for: side)
        guard isFileSearchPresented else { return allItems }

        let query = fileSearchAppliedQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }

        return allItems.filter { item in
            FileNameSearch.matches(item.name, query: query)
                || FileNameSearch.matches(displayName(for: item), query: query)
        }
    }

    private func displayName(for item: FileItem) -> String {
        guard let root = model.flatViewRoot(for: side) else { return item.name }

        let rootPath = root.standardizedFileURL.path
        let itemPath = item.url.standardizedFileURL.path
        let prefix = rootPath == "/" ? "/" : rootPath + "/"
        guard itemPath.hasPrefix(prefix) else { return item.name }

        let relativePath = String(itemPath.dropFirst(prefix.count))
        return relativePath.isEmpty ? item.name : relativePath
    }

    private var similarReviewItems: [FileItem] {
        similarReviewVisibleItems
    }

    @ViewBuilder
    private func similarFileRowBackground(for item: FileItem) -> some View {
        if isSimilarFileNavigatorEnabled,
           let marker = similarFileGroupMarker(for: item.url) {
            marker.color.opacity(marker.isCurrent ? 0.28 : 0.14)
        } else {
            Color.clear
        }
    }

    private func similarFileGroupMarker(for url: URL) -> SimilarFileGroupMarker? {
        guard isSimilarFileNavigatorEnabled else { return nil }
        return similarFileGroupMarkersByURL[url]
    }

    private func isSimilarFileVisuallyDeleted(_ url: URL) -> Bool {
        isSimilarFileNavigatorEnabled && visuallyDeletedSimilarFileURLs.contains(url)
    }

    private func similarFileNavigatorControls(scrollProxy: ScrollViewProxy) -> some View {
        let groups = similarFileGroups
        let hasGroups = !groups.isEmpty
        let currentPosition = hasGroups ? min(similarFileGroupIndex, groups.count - 1) + 1 : 0
        let unhandledCount = groups.filter { !handledSimilarFileGroupIDs.contains($0.id) }.count

        return HStack(spacing: 4) {
            IconButton(
                systemName: isSimilarFileNavigatorEnabled ? "doc.on.doc.fill" : "doc.on.doc",
                help: "Find similar file names"
            ) {
                toggleSimilarFileNavigator(with: scrollProxy)
            }

            if isSimilarFileNavigatorEnabled {
                IconButton(systemName: "chevron.up", help: "Previous similar group") {
                    moveSimilarFileGroup(by: -1, with: scrollProxy)
                }
                .disabled(groups.count < 2)

                IconButton(systemName: "chevron.down", help: "Next similar group") {
                    moveSimilarFileGroup(by: 1, with: scrollProxy)
                }
                .disabled(groups.count < 2)

                Text("\(currentPosition)/\(groups.count) · \(unhandledCount) left")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(minWidth: 72, alignment: .leading)

                Button("Older") {
                    selectOlderSimilarFiles(with: scrollProxy)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(!hasGroups)
                .help("Select older files in this similar-name group")

                Button("Smaller") {
                    selectSmallerSimilarFiles(with: scrollProxy)
                }
                .buttonStyle(.borderless)
                .font(.caption2)
                .disabled(!hasGroups)
                .help("Select smaller files in this similar-name group")

                IconButton(systemName: "checkmark.circle", help: "Mark current similar group handled") {
                    markCurrentSimilarFileGroupHandled(with: scrollProxy)
                }
                .disabled(!hasGroups)
            }
        }
    }

    private var fileSearchOverlay: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Filter current folder", text: $fileSearchQuery)
                .textFieldStyle(.plain)
                .focused($isFileSearchFocused)
                .onKeyPress(.return, phases: .down) { keyPress in
                    guard keyPress.modifiers.isEmpty else { return .ignored }
                    beginFileSearchListSelection()
                    return .handled
                }
                .onKeyPress(.escape, phases: .down) { _ in
                    dismissFileSearch()
                    return .handled
                }
                .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { keyPress in
                    guard keyPress.modifiers.isEmpty else { return .ignored }
                    beginFileSearchListSelection()
                    moveFileSearchSelection(keyPress.key == .upArrow ? -1 : 1)
                    return .handled
                }
            Text("\(visibleItems.count)/\(model.items(for: side).count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Button {
                dismissFileSearch()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Close filter")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: 360)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.16))
        )
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
        .opacity(0.94)
    }

    private var footerStats: some View {
        let summary = FilePaneSummary(items: visibleItems)
        let freeSpaceText = formattedFreeSpace

        return HStack(spacing: 12) {
            summaryMetric("Files", value: "\(summary.fileCount)")
            summaryMetric("Size", value: summary.formattedFileSize)
            summaryMetric("Folders", value: "\(summary.folderCount)")
            summaryMetric("Free space", value: freeSpaceText)
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityLabel("Files \(summary.fileCount), total size \(summary.formattedFileSize), folders \(summary.folderCount), free space \(freeSpaceText)")
    }

    private var formattedFreeSpace: String {
        guard let freeSpaceCapacity else { return "--" }
        return ByteCountFormatter.string(fromByteCount: freeSpaceCapacity, countStyle: .file)
    }

    private func summaryMetric(_ title: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(title)
            Text(value)
                .fontWeight(.semibold)
        }
        .lineLimit(1)
    }

    private var sortHeader: some View {
        HStack(spacing: FileListMetrics.iconColumnSpacing) {
            Color.clear.frame(width: FileListMetrics.iconColumnWidth)
            FileListColumnLayout(
                columnWidths: model.columnWidths(for: side),
                showsEncoding: model.isEncodingColumnVisible,
                showsResizeHandles: true,
                onResizeColumn: { column, delta in
                    model.adjustFileListColumn(column, for: side, by: delta)
                },
                onResizeEnded: model.commitUILayoutPreferences,
                name: {
                    SortHeaderButton(title: "Name", field: .name, rule: model.sortRule(for: side)) {
                        model.selectSortField(.name, for: side)
                    }
                },
                type: {
                    SortHeaderButton(title: "Type", field: .type, rule: model.sortRule(for: side)) {
                        model.selectSortField(.type, for: side)
                    }
                },
                encoding: {
                    Text("Encoding")
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                },
                size: {
                    SortHeaderButton(title: "Size", field: .size, rule: model.sortRule(for: side)) {
                        model.selectSortField(.size, for: side)
                    }
                },
                modified: {
                    SortHeaderButton(title: "Modified", field: .modifiedAt, rule: model.sortRule(for: side)) {
                        model.selectSortField(.modifiedAt, for: side)
                    }
                }
            )
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.leading, FileListMetrics.horizontalPadding)
        .padding(.trailing, FileListMetrics.horizontalPadding + FileListMetrics.verticalScrollerGutter)
        .padding(.vertical, 2)
        .frame(height: 22)
        .background(.bar)
        .contextMenu {
            Toggle(
                "Show Encoding Column",
                isOn: Binding(
                    get: { model.isEncodingColumnVisible },
                    set: { model.setEncodingColumnVisible($0) }
                )
            )
        }
    }

    private func beginRenamingSelectedItem() -> Bool {
        guard renamingURL == nil else { return false }
        let selected = model.pane(for: side).selectedItemURLs
        guard selected.count == 1,
              let item = visibleItems.first(where: { selected.contains($0.url) }) else {
            return false
        }

        beginRenaming(item)
        model.isInlineRenaming = true
        return true
    }

    private func beginFileSearch() {
        model.activatePane(side)
        if !isFileSearchPresented {
            fileSearchQuery = ""
            fileSearchAppliedQuery = ""
            isFileSearchPresented = true
        }

        dismissPathEditingForFileSearch()
        synchronizeFileSearchSelection()
        model.logFileSearchEvent("presented", metadata: [
            "side": side.rawValue,
            "path": model.pane(for: side).selectedURL.path
        ])

        focusFileSearchInput(selectAll: true)
    }

    private func beginFileSearchListSelection() {
        guard isFileSearchPresented else { return }
        applyFileSearchQueryNow()
        synchronizeFileSearchSelection(preferFirstMatch: true)
        model.logFileSearchEvent("list-selection.begin", metadata: [
            "side": side.rawValue,
            "query": fileSearchQuery,
            "count": "\(visibleItems.count)"
        ])
        restoreFileListFocus()
    }

    private func focusFileSearchInput(selectAll: Bool) {
        guard isFileSearchPresented else { return }

        model.activatePane(side)
        dismissPathEditingForFileSearch()
        model.logFileSearchEvent("input.focus", metadata: [
            "side": side.rawValue,
            "query": fileSearchQuery
        ])

        DispatchQueue.main.async {
            isFileSearchFocused = true
            guard selectAll else { return }
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
    }

    private func scheduleFileSearchSynchronization() {
        guard isFileSearchPresented else { return }
        fileSearchDebounceWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            fileSearchAppliedQuery = fileSearchQuery
            synchronizeFileSearchSelection()
        }
        fileSearchDebounceWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: workItem)
    }

    private func applyFileSearchQueryNow() {
        fileSearchDebounceWorkItem?.cancel()
        fileSearchDebounceWorkItem = nil
        fileSearchAppliedQuery = fileSearchQuery
    }

    private func moveFileSearchSelection(_ delta: Int) {
        applyFileSearchQueryNow()
        guard !visibleItems.isEmpty else { return }

        let currentSelection = model.pane(for: side).selectedItemURLs
        let currentIndex = visibleItems.firstIndex { currentSelection.contains($0.url) }
        let baseIndex = currentIndex ?? (delta < 0 ? visibleItems.count : -1)
        let nextIndex = min(max(baseIndex + delta, 0), visibleItems.count - 1)
        model.replaceSelection([visibleItems[nextIndex].url], on: side, source: "file-search")
    }

    private func synchronizeFileSearchSelection(preferFirstMatch: Bool = false) {
        guard isFileSearchPresented else { return }

        let visibleURLs = Set(visibleItems.map(\.url))
        let currentSelection = model.pane(for: side).selectedItemURLs
        guard currentSelection.isEmpty || !currentSelection.isSubset(of: visibleURLs) || preferFirstMatch else {
            return
        }

        if let first = visibleItems.first {
            model.replaceSelection([first.url], on: side, source: "file-search")
        } else {
            model.replaceSelection([], on: side, source: "file-search")
        }
    }

    private func dismissFileSearch(restoreFocus: Bool = true) {
        guard isFileSearchPresented else { return }
        fileSearchDebounceWorkItem?.cancel()
        fileSearchDebounceWorkItem = nil
        isFileSearchPresented = false
        fileSearchQuery = ""
        fileSearchAppliedQuery = ""
        isFileSearchFocused = false
        model.logFileSearchEvent("dismissed", metadata: [
            "side": side.rawValue
        ])
        if restoreFocus {
            restoreFileListFocus()
        }
    }

    private func toggleSimilarFileNavigator(with scrollProxy: ScrollViewProxy) {
        if isSimilarFileNavigatorEnabled {
            isSimilarFileNavigatorEnabled = false
            model.setSimilarFileReviewActive(false, on: side)
            model.statusMessage = "Similar-name review off"
            clearSimilarFileReviewCachesAfterExit()
            return
        }

        refreshSimilarFileGroups()
        guard !similarFileGroups.isEmpty else {
            model.statusMessage = "No similar file-name groups in this folder"
            return
        }

        isSimilarFileNavigatorEnabled = true
        model.setSimilarFileReviewActive(true, on: side)
        dismissFileSearch(restoreFocus: false)
        model.replaceSelection([], on: side, source: "similar-file-navigator")
        similarFileGroupIndex = min(similarFileGroupIndex, similarFileGroups.count - 1)
        rebuildSimilarFileReviewCaches()
        selectSimilarFileGroup(similarFileGroups[similarFileGroupIndex], with: scrollProxy)
    }

    private func moveSimilarFileGroup(by delta: Int, with scrollProxy: ScrollViewProxy) {
        let groups = similarFileGroups
        guard !groups.isEmpty else {
            synchronizeSimilarFileNavigator(with: scrollProxy)
            return
        }

        let nextIndex = (similarFileGroupIndex + delta + groups.count) % groups.count
        similarFileGroupIndex = nextIndex
        rebuildSimilarFileReviewCaches()
        selectSimilarFileGroup(groups[nextIndex], with: scrollProxy)
    }

    private func markCurrentSimilarFileGroupHandled(with scrollProxy: ScrollViewProxy) {
        let groups = similarFileGroups
        guard let group = currentSimilarFileGroup(in: groups) else { return }
        handledSimilarFileGroupIDs.insert(group.id)

        let searchOrder = Array((similarFileGroupIndex + 1)..<groups.count) + Array(0...similarFileGroupIndex)
        if let nextUnhandledIndex = searchOrder.first(where: { !handledSimilarFileGroupIDs.contains(groups[$0].id) }) {
            similarFileGroupIndex = nextUnhandledIndex
            rebuildSimilarFileReviewCaches()
            selectSimilarFileGroup(groups[nextUnhandledIndex], with: scrollProxy)
        } else {
            model.statusMessage = "All similar-name groups in this folder are marked handled"
        }
    }

    private func selectOlderSimilarFiles(with scrollProxy: ScrollViewProxy) {
        let groups = similarFileGroups
        guard let group = currentSimilarFileGroup(in: groups) else { return }
        let newest = group.items.max { left, right in
            switch (left.modifiedAt, right.modifiedAt) {
            case let (left?, right?):
                return left < right
            case (nil, _?):
                return true
            case (_?, nil), (nil, nil):
                return false
            }
        }
        selectSimilarFileSubset(
            group.items.filter { $0.url != newest?.url },
            statusPrefix: "Selected older similar-name files",
            with: scrollProxy
        )
    }

    private func selectSmallerSimilarFiles(with scrollProxy: ScrollViewProxy) {
        let groups = similarFileGroups
        guard let group = currentSimilarFileGroup(in: groups) else { return }
        let largest = group.items.max { left, right in
            switch (left.size, right.size) {
            case let (left?, right?):
                return left < right
            case (nil, _?):
                return true
            case (_?, nil), (nil, nil):
                return false
            }
        }
        selectSimilarFileSubset(
            group.items.filter { $0.url != largest?.url },
            statusPrefix: "Selected smaller similar-name files",
            with: scrollProxy
        )
    }

    private func synchronizeSimilarFileNavigator(with scrollProxy: ScrollViewProxy) {
        guard isSimilarFileNavigatorEnabled else {
            similarFileGroups = []
            similarReviewVisibleItems = []
            similarFileGroupMarkersByURL = [:]
            similarFileGroupIndexByURL = [:]
            similarFileGroupIndex = 0
            return
        }

        refreshSimilarFileGroups()
        let groups = similarFileGroups
        handledSimilarFileGroupIDs.formIntersection(Set(groups.map(\.id)))

        guard !groups.isEmpty else {
            isSimilarFileNavigatorEnabled = false
            model.setSimilarFileReviewActive(false, on: side)
            similarFileGroupIndex = 0
            model.statusMessage = "No remaining similar file-name groups in this folder"
            return
        }

        similarFileGroupIndex = min(similarFileGroupIndex, groups.count - 1)
        rebuildSimilarFileReviewCaches()
        selectSimilarFileGroup(groups[similarFileGroupIndex], with: scrollProxy)
    }

    private func resetSimilarFileNavigator() {
        isSimilarFileNavigatorEnabled = false
        model.setSimilarFileReviewActive(false, on: side)
        similarFileGroupIndex = 0
        similarFileGroups = []
        similarReviewVisibleItems = []
        similarFileGroupMarkersByURL = [:]
        similarFileGroupIndexByURL = [:]
        handledSimilarFileGroupIDs.removeAll()
        visuallyDeletedSimilarFileURLs.removeAll()
        fileListKeyboardAnchorURL = nil
    }

    private func clearSimilarFileReviewCachesAfterExit() {
        DispatchQueue.main.async {
            guard !isSimilarFileNavigatorEnabled else { return }
            similarFileGroups = []
            similarReviewVisibleItems = []
            similarFileGroupMarkersByURL = [:]
            similarFileGroupIndexByURL = [:]
        }
    }

    private func refreshSimilarFileGroups() {
        let startedAt = Date()
        model.logSimilarFileReviewEvent("groups.refresh.started", metadata: [
            "side": side.rawValue,
            "itemCount": "\(model.items(for: side).count)"
        ])
        similarFileGroups = SimilarFileNameDetector.groups(in: model.items(for: side))
        rebuildSimilarFileReviewCaches()
        let durationMs = Int(Date().timeIntervalSince(startedAt) * 1_000)
        model.logSimilarFileReviewEvent("groups.refresh.finished", metadata: [
            "side": side.rawValue,
            "groupCount": "\(similarFileGroups.count)",
            "visibleCount": "\(similarReviewVisibleItems.count)",
            "durationMs": "\(durationMs)"
        ])
    }

    private func rebuildSimilarFileReviewCaches() {
        similarReviewVisibleItems = similarFileGroups.flatMap(\.items)

        let currentIndex = similarFileGroups.indices.contains(similarFileGroupIndex) ? similarFileGroupIndex : nil
        var markersByURL: [URL: SimilarFileGroupMarker] = [:]
        var indexesByURL: [URL: Int] = [:]
        markersByURL.reserveCapacity(similarReviewVisibleItems.count)
        indexesByURL.reserveCapacity(similarReviewVisibleItems.count)

        for index in similarFileGroups.indices {
            let marker = SimilarFileGroupMarker(
                color: similarFileGroupColors[index % similarFileGroupColors.count],
                isCurrent: index == currentIndex
            )
            for item in similarFileGroups[index].items {
                markersByURL[item.url] = marker
                indexesByURL[item.url] = index
            }
        }

        similarFileGroupMarkersByURL = markersByURL
        similarFileGroupIndexByURL = indexesByURL
    }

    private func reconcileVisuallyDeletedSimilarFiles() {
        var state = SimilarFileReviewState(
            groups: similarFileGroups,
            visuallyDeletedURLs: visuallyDeletedSimilarFileURLs
        )
        state.reconcileDeletedMarkers(with: model.items(for: side))
        visuallyDeletedSimilarFileURLs = state.visuallyDeletedURLs
    }

    private func currentSimilarFileGroup(in groups: [SimilarFileNameGroup]) -> SimilarFileNameGroup? {
        guard !groups.isEmpty else { return nil }
        return groups[min(similarFileGroupIndex, groups.count - 1)]
    }

    private func selectSimilarFileGroup(_ group: SimilarFileNameGroup, with scrollProxy: ScrollViewProxy) {
        if let firstURL = group.items.first?.url {
            fileListKeyboardAnchorURL = firstURL
            pendingRevealURL = firstURL
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollProxy.scrollTo(firstURL, anchor: .top)
                }
            }
        }
        model.statusMessage = "Similar-name group \(similarFileGroupIndex + 1)/\(similarFileGroups.count): \(group.items.count) item(s)"
        restoreFileListFocus()
    }

    private func selectSimilarFileSubset(
        _ items: [FileItem],
        statusPrefix: String,
        with scrollProxy: ScrollViewProxy
    ) {
        let urls = Set(items.map(\.url))
        model.replaceSelection(urls, on: side, source: "similar-file-navigator")
        if let firstURL = items.first?.url {
            fileListKeyboardAnchorURL = firstURL
            pendingRevealURL = firstURL
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.18)) {
                    scrollProxy.scrollTo(firstURL, anchor: .center)
                }
            }
        }
        model.statusMessage = "\(statusPrefix): \(items.count) item(s)"
        restoreFileListFocus()
    }

    private func moveSimilarFileSelection(_ delta: Int) {
        let orderedURLs = similarReviewItems.map(\.url)
        let currentSelection = model.pane(for: side).selectedItemURLs
        guard let replacementSelection = FileKeyboardSelectionNavigator.selectionAfterMove(
            anchorURL: fileListKeyboardAnchorURL,
            currentSelection: currentSelection,
            orderedURLs: orderedURLs,
            unavailableURLs: visuallyDeletedSimilarFileURLs,
            delta: delta
        ) else {
            model.logSimilarFileReviewEvent("keyboard-move.ignored", metadata: [
                "side": side.rawValue,
                "delta": "\(delta)",
                "anchorPath": fileListKeyboardAnchorURL?.path ?? "",
                "selectionCount": "\(currentSelection.count)"
            ])
            return
        }

        guard let nextURL = replacementSelection.first else { return }
        fileListKeyboardAnchorURL = nextURL
        updateSimilarFileGroupIndex(containing: nextURL)
        pendingRevealURL = nextURL
        model.replaceSelection(replacementSelection, on: side, source: "similar-file-review.keyboard")
        model.logSimilarFileReviewEvent("keyboard-move.applied", metadata: [
            "side": side.rawValue,
            "delta": "\(delta)",
            "path": nextURL.path
        ])
        restoreFileListFocus()
    }

    private func moveFileListSelection(_ delta: Int) {
        let orderedURLs = visibleItems.map(\.url)
        let currentSelection = model.pane(for: side).selectedItemURLs
        guard let replacementSelection = FileKeyboardSelectionNavigator.selectionAfterMove(
            anchorURL: fileListKeyboardAnchorURL,
            currentSelection: currentSelection,
            orderedURLs: orderedURLs,
            delta: delta
        ) else {
            return
        }

        guard let nextURL = replacementSelection.first else { return }
        fileListKeyboardAnchorURL = nextURL
        pendingRevealURL = nextURL
        model.replaceSelection(replacementSelection, on: side, source: "file-list.keyboard")
        restoreFileListFocus()
    }

    private func updateSimilarFileGroupIndex(containing url: URL) {
        guard let index = similarFileGroupIndexByURL[url] else {
            return
        }
        guard similarFileGroupIndex != index else { return }
        similarFileGroupIndex = index
        rebuildSimilarFileReviewCaches()
    }

    private func handleFileListKeyDown(_ event: NSEvent) -> Bool {
        guard isFileListFocused,
              renamingURL == nil,
              !isFileSearchPresented else {
            return false
        }

        let relevantModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch event.keyCode {
        case 126:
            if relevantModifiers.isEmpty {
                moveFocusedFileListSelection(-1)
                return true
            }
            guard relevantModifiers == .command else { return false }
            model.navigateUp(side)
            return true
        case 125:
            if relevantModifiers.isEmpty {
                moveFocusedFileListSelection(1)
                return true
            }
            guard relevantModifiers == .command else { return false }
            model.navigateIntoSelectedDirectory(side)
            return true
        default:
            return false
        }
    }

    private func moveFocusedFileListSelection(_ delta: Int) {
        if isSimilarFileNavigatorEnabled {
            moveSimilarFileSelection(delta)
        } else {
            moveFileListSelection(delta)
        }
    }

    private func dismissPathEditingForFileSearch() {
        guard isEditingPath else { return }
        isEditingPath = false
        pathText = model.isAndroidPane(side)
            ? (AndroidFileURL.parse(model.pane(for: side).selectedURL)?.path ?? "/sdcard")
            : model.pane(for: side).selectedURL.path
        isPathFieldFocused = false
    }

    private func isControlOnly(_ modifiers: EventModifiers) -> Bool {
        modifiers.contains(.control)
            && !modifiers.contains(.command)
            && !modifiers.contains(.option)
            && !modifiers.contains(.shift)
    }

    private func beginRenaming(_ url: URL) {
        pendingRevealURL = url
        if let item = model.items(for: side).first(where: { $0.url == url }) {
            beginRenaming(item)
        } else {
            renamingURL = url
            renameText = url.lastPathComponent
        }
        model.isInlineRenaming = true
    }

    private func queueRename(_ url: URL) {
        pendingRenameURL = url
        pendingRevealURL = url
        DispatchQueue.main.async {
            beginPendingRenameIfReady()
        }
    }

    private func beginPendingRenameIfReady() {
        guard let pendingRenameURL,
              let item = model.items(for: side).first(where: { sameFileIdentity($0.url, pendingRenameURL) }) else {
            return
        }
        self.pendingRenameURL = nil
        beginRenaming(item.url)
    }

    private func revealPendingItemIfReady(with scrollProxy: ScrollViewProxy) {
        guard let url = pendingRevealURL,
              let item = model.items(for: side).first(where: { sameFileIdentity($0.url, url) }) else {
            if let url = pendingRevealURL {
                model.logPaneFocusEvent("pending-reveal.waiting", metadata: [
                    "side": side.rawValue,
                    "path": url.path,
                    "itemsCount": "\(model.items(for: side).count)",
                    "visibleCount": "\(visibleItems.count)",
                    "isSelected": "\(selectionContains(url))"
                ])
            }
            return
        }

        pendingRevealURL = nil
        let revealURL = item.url
        model.logPaneFocusEvent("pending-reveal.applied", metadata: [
            "side": side.rawValue,
            "path": url.path,
            "revealURL": revealURL.absoluteString,
            "isSelected": "\(selectionContains(url))",
            "visibleIndex": "\(visibleItems.firstIndex(where: { sameFileIdentity($0.url, revealURL) }) ?? -1)"
        ])
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(revealURL, anchor: .center)
            }
        }
    }

    private func beginRenaming(_ item: FileItem) {
        renamingURL = item.url
        renameText = item.name
    }

    private func commitRename() {
        guard let renamingURL else { return }
        let newName = renameText
        let expectedRenamedURL = expectedRenameURL(for: renamingURL, newName: newName)
        let traceID = UUID().uuidString
        logInlineRenameSnapshot("inline-rename.commit.started", traceID: traceID, targetURL: expectedRenamedURL)

        if let moveSources = pendingNewFolderMoveSources {
            if model.commitNewFolderWithSelection(
                folder: renamingURL,
                newName: newName,
                movingSources: moveSources,
                on: side
            ) {
                pendingNewFolderMoveSources = nil
                clearRenameState()
                restoreFileListFocus()
            }
            return
        }

        clearRenameState()
        pendingRevealURL = expectedRenamedURL
        let renamedURL = model.renameItem(renamingURL, to: newName, on: side)
        let targetURL = renamedURL ?? expectedRenamedURL
        logInlineRenameSnapshot("inline-rename.commit.returned", traceID: traceID, targetURL: targetURL)
        restoreFileListFocus(requestID: traceID, reason: "inline-rename.commit", revealURL: targetURL)
    }

    private func expectedRenameURL(for url: URL, newName: String) -> URL {
        if let parsed = AndroidFileURL.parse(url) {
            let parent = (parsed.path as NSString).deletingLastPathComponent
            let path = parent == "/" ? "/\(newName)" : "\(parent)/\(newName)"
            return AndroidFileURL.url(deviceSerial: parsed.deviceSerial, path: path)
        }
        let isDirectoryLike = model.items(for: side).first(where: { sameFileIdentity($0.url, url) })?.isDirectoryLike ?? false
        return url.deletingLastPathComponent()
            .appendingPathComponent(newName, isDirectory: isDirectoryLike)
            .standardizedFileURL
    }

    private func cancelRename() {
        if let moveSources = pendingNewFolderMoveSources, let folderURL = renamingURL {
            pendingNewFolderMoveSources = nil
            clearRenameState()
            model.cancelNewFolderWithSelection(
                folder: folderURL,
                restoringSelection: moveSources,
                on: side
            )
            restoreFileListFocus()
            return
        }

        clearRenameState()
        restoreFileListFocus()
    }

    private func clearRenameState() {
        renamingURL = nil
        pendingRenameURL = nil
        pendingRevealURL = nil
        pendingNewFolderMoveSources = nil
        renameText = ""
        model.isInlineRenaming = false
    }

    private func beginPathEditing() {
        model.activatePane(side)
        if !isEditingPath {
            pathText = model.pane(for: side).selectedURL.path
            isEditingPath = true
        }
        DispatchQueue.main.async {
            isPathFieldFocused = true
        }
    }

    private func commitPathEditing() {
        guard model.navigateToFolderPath(pathText, on: side) else {
            isPathFieldFocused = true
            return
        }

        isEditingPath = false
        pathText = model.isAndroidPane(side)
            ? (AndroidFileURL.parse(model.pane(for: side).selectedURL)?.path ?? "/sdcard")
            : model.pane(for: side).selectedURL.path
        restoreFileListFocus()
    }

    private func cancelPathEditing() {
        isEditingPath = false
        pathText = model.isAndroidPane(side)
            ? (AndroidFileURL.parse(model.pane(for: side).selectedURL)?.path ?? "/sdcard")
            : model.pane(for: side).selectedURL.path
        restoreFileListFocus()
    }

    private func activateItem(_ url: URL) {
        guard renamingURL == nil else { return }
        model.activateItem(url, on: side)
        restoreFileListFocus()
    }

    private func selectItemFromRowMouseDown(
        _ url: URL,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard renamingURL == nil else { return }

        let startedAt = Date()
        fileListKeyboardAnchorURL = url
        if isSimilarFileNavigatorEnabled {
            updateSimilarFileGroupIndex(containing: url)
        }
        isFileListFocused = true
        model.activatePane(side)
        let visibleCount = visibleItems.count
        let orderedURLs = modifierFlags.contains(.shift) ? visibleItems.map(\.url) : []

        applyRowSelection(
            FileRowSelectionReducer.selectionAfterMouseDown(
                target: url,
                currentSelection: model.pane(for: side).selectedItemURLs,
                orderedURLs: orderedURLs,
                modifierFlags: modifierFlags
            ),
            source: "file-row.mouse-down"
        )
        logRowSelectionApplyTiming(source: "file-row.mouse-down", url: url, visibleCount: visibleCount, startedAt: startedAt)
        logRowSelectionTiming(source: "file-row.mouse-down", url: url, visibleCount: visibleCount, startedAt: startedAt)
    }

    private func selectItemFromRowMouseUp(
        _ url: URL,
        modifierFlags: NSEvent.ModifierFlags
    ) {
        guard renamingURL == nil else { return }

        let startedAt = Date()
        fileListKeyboardAnchorURL = url
        if isSimilarFileNavigatorEnabled {
            updateSimilarFileGroupIndex(containing: url)
        }
        let visibleCount = visibleItems.count
        applyRowSelection(
            FileRowSelectionReducer.selectionAfterMouseUp(
                target: url,
                currentSelection: model.pane(for: side).selectedItemURLs,
                orderedURLs: [],
                modifierFlags: modifierFlags
            ),
            source: "file-row.mouse-up"
        )
        logRowSelectionApplyTiming(source: "file-row.mouse-up", url: url, visibleCount: visibleCount, startedAt: startedAt)
        logRowSelectionTiming(source: "file-row.mouse-up", url: url, visibleCount: visibleCount, startedAt: startedAt)
    }

    private func applyRowSelection(_ selection: Set<URL>?, source: String) {
        guard let selection else { return }
        model.replaceSelection(selection, on: side, source: source)
    }

    private func logRowSelectionApplyTiming(source: String, url: URL, visibleCount: Int, startedAt: Date) {
        let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
        guard elapsedMilliseconds >= 20 else { return }
        model.logSelectionPerformanceEvent("row-selection.apply-slow", metadata: [
            "side": side.rawValue,
            "source": source,
            "path": url.path,
            "elapsedMs": String(format: "%.1f", elapsedMilliseconds),
            "visibleCount": "\(visibleCount)",
            "selectionCount": "\(model.pane(for: side).selectedItemURLs.count)",
            "activePane": model.activePaneSide.rawValue
        ])
    }

    private func logRowSelectionTiming(source: String, url: URL, visibleCount: Int, startedAt: Date) {
        DispatchQueue.main.async {
            let elapsedMilliseconds = Date().timeIntervalSince(startedAt) * 1_000
            guard elapsedMilliseconds >= 50 else { return }
            model.logSelectionPerformanceEvent("row-selection.slow", metadata: [
                "side": side.rawValue,
                "source": source,
                "path": url.path,
                "elapsedMs": String(format: "%.1f", elapsedMilliseconds),
                "visibleCount": "\(visibleCount)",
                "selectionCount": "\(model.pane(for: side).selectedItemURLs.count)",
                "activePane": model.activePaneSide.rawValue
            ])
        }
    }

    private func trashSelectionFromPane(selectionHint: Set<URL>? = nil) {
        let selection = selectionHint ?? model.pane(for: side).selectedItemURLs
        if let selectionHint, selectionHint != model.pane(for: side).selectedItemURLs {
            model.replaceSelection(selectionHint, on: side, source: "file-row.trash")
        }
        markSimilarFilesVisuallyDeleted(selection, source: "pane-trash")
        model.trashSelection(
            from: side,
            refreshPolicy: FileOperationRefreshPolicy.trashPolicy(isSimilarFileReviewActive: isSimilarFileNavigatorEnabled)
        )
    }

    private func markSimilarFilesVisuallyDeleted(_ selection: Set<URL>, source: String) {
        guard isSimilarFileNavigatorEnabled, !selection.isEmpty else { return }
        var state = SimilarFileReviewState(
            groups: similarFileGroups,
            visuallyDeletedURLs: visuallyDeletedSimilarFileURLs
        )
        state.markVisuallyDeleted(selection)
        visuallyDeletedSimilarFileURLs = state.visuallyDeletedURLs
        let replacementSelection = state.replacementSelection(afterDeleting: selection)
        fileListKeyboardAnchorURL = replacementSelection.first
        if let replacementURL = replacementSelection.first {
            updateSimilarFileGroupIndex(containing: replacementURL)
        }
        model.replaceSelection(replacementSelection, on: side, source: "similar-file-review.visual-delete-replacement")
        model.logSimilarFileReviewEvent("visual-delete.marked", metadata: [
            "side": side.rawValue,
            "source": source,
            "count": "\(selection.count)",
            "totalMarked": "\(visuallyDeletedSimilarFileURLs.count)",
            "replacementCount": "\(replacementSelection.count)",
            "replacement": replacementSelection.map(\.path).joined(separator: "|")
        ])
    }

    private func dragURLs(startingWith url: URL) -> [URL] {
        let selection = model.pane(for: side).selectedItemURLs
        guard selection.contains(url) else { return [url] }
        let orderedSelection = model.items(for: side).map(\.url).filter { selection.contains($0) }
        return orderedSelection.isEmpty ? [url] : orderedSelection
    }

    private func logFileClipboardShortcut(_ operation: String, modifiers: String) -> String {
        let requestID = UUID().uuidString
        model.logShortcutEvent("key-down", metadata: [
            "requestID": requestID,
            "side": side.rawValue,
            "key": operation == "copy" ? "c" : "v",
            "modifiers": modifiers,
            "operation": operation
        ])
        return requestID
    }

    private func restoreFileListFocus(requestID: String? = nil, reason: String? = nil, revealURL: URL? = nil) {
        DispatchQueue.main.async {
            if let revealURL {
                pendingRevealURL = revealURL
            }
            isPathFieldFocused = false
            isFileSearchFocused = false
            isFileListFocused = true
            logFileListFocusRequest(requestID: requestID, reason: reason, revealURL: revealURL)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            isPathFieldFocused = false
            isFileSearchFocused = false
            isFileListFocused = true
        }
    }

    private func logFileListFocusRequest(requestID: String?, reason: String?, revealURL: URL?) {
        var metadata = [
            "side": side.rawValue
        ]
        if let requestID {
            metadata["requestID"] = requestID
        }
        if let reason {
            metadata["reason"] = reason
        }
        if let revealURL {
            metadata["revealPath"] = revealURL.path
        }
        model.logPaneFocusEvent("file-list.focus-set.requested", metadata: metadata)
    }

    private func logInlineRenameSnapshot(
        _ event: String,
        traceID: String,
        targetURL: URL,
    ) {
        let items = model.items(for: side)
        let selection = model.pane(for: side).selectedItemURLs
        let metadata = [
            "traceID": traceID,
            "side": side.rawValue,
            "targetPath": targetURL.path,
            "selectedContainsTarget": "\(selectionContains(targetURL))",
            "itemsContainsTarget": "\(items.contains(where: { sameFileIdentity($0.url, targetURL) }))",
            "visibleContainsTarget": "\(visibleItems.contains(where: { sameFileIdentity($0.url, targetURL) }))",
            "itemIndex": "\(items.firstIndex(where: { sameFileIdentity($0.url, targetURL) }) ?? -1)",
            "visibleIndex": "\(visibleItems.firstIndex(where: { sameFileIdentity($0.url, targetURL) }) ?? -1)",
            "selectionCount": "\(selection.count)",
            "selectionPaths": selection.map(\.path).sorted().joined(separator: "|"),
            "itemsCount": "\(items.count)",
            "visibleCount": "\(visibleItems.count)",
            "activePane": model.activePaneSide.rawValue,
            "isFileListFocused": "\(isFileListFocused)",
            "isPathFieldFocused": "\(isPathFieldFocused)",
            "isFileSearchFocused": "\(isFileSearchFocused)",
            "renamingPath": renamingURL?.path ?? "",
            "pendingRevealPath": pendingRevealURL?.path ?? "",
            "isInlineRenaming": "\(model.isInlineRenaming)"
        ]
        model.logPaneFocusEvent(event, metadata: metadata)
    }

    private func selectionContains(_ url: URL) -> Bool {
        selectionContains(url, in: model.pane(for: side).selectedItemURLs)
    }

    private func selectionContains(_ url: URL, in selection: Set<URL>) -> Bool {
        if selection.contains(url) {
            return true
        }

        let standardizedURL = url.standardizedFileURL
        if standardizedURL != url, selection.contains(standardizedURL) {
            return true
        }

        return selection.contains { sameFileIdentity($0, url) }
    }

    private func sameFileIdentity(_ lhs: URL, _ rhs: URL) -> Bool {
        lhs.standardizedFileURL.path == rhs.standardizedFileURL.path
    }
}

private struct FilePaneSummary {
    let fileCount: Int
    let fileTotalSize: Int64
    let folderCount: Int

    init(items: [FileItem]) {
        let files = items.filter { !$0.isDirectoryLike }
        fileCount = files.count
        fileTotalSize = files.compactMap(\.size).reduce(0, +)
        folderCount = items.filter(\.isDirectoryLike).count
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileTotalSize, countStyle: .file)
    }
}

private struct RowMouseHandler: NSViewRepresentable {
    let mouseDown: (NSEvent.ModifierFlags) -> Void
    let mouseUp: (NSEvent.ModifierFlags) -> Void
    let doubleClick: () -> Void
    let dragURLsProvider: () -> [URL]
    let onDragStarted: ([URL]) -> Void

    func makeNSView(context: Context) -> MouseHandlingView {
        let view = MouseHandlingView()
        view.mouseDownAction = mouseDown
        view.mouseUpAction = mouseUp
        view.doubleClickAction = doubleClick
        view.dragURLsProvider = dragURLsProvider
        view.onDragStarted = onDragStarted
        return view
    }

    func updateNSView(_ nsView: MouseHandlingView, context: Context) {
        nsView.mouseDownAction = mouseDown
        nsView.mouseUpAction = mouseUp
        nsView.doubleClickAction = doubleClick
        nsView.dragURLsProvider = dragURLsProvider
        nsView.onDragStarted = onDragStarted
    }

    final class MouseHandlingView: NSView, NSDraggingSource {
        var mouseDownAction: ((NSEvent.ModifierFlags) -> Void)?
        var mouseUpAction: ((NSEvent.ModifierFlags) -> Void)?
        var doubleClickAction: (() -> Void)?
        var dragURLsProvider: (() -> [URL])?
        var onDragStarted: (([URL]) -> Void)?

        private var mouseDownEvent: NSEvent?
        private var mouseDownLocation: NSPoint = .zero
        private var didStartDrag = false
        private static let dragThreshold: CGFloat = 4.0

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 {
                doubleClickAction?()
            } else {
                mouseDownEvent = event
                mouseDownLocation = event.locationInWindow
                didStartDrag = false
                mouseDownAction?(event.modifierFlags)
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didStartDrag else { return }
            guard mouseDownEvent?.modifierFlags.contains(.command) != true,
                  mouseDownEvent?.modifierFlags.contains(.shift) != true else {
                return
            }
            let delta = hypot(
                event.locationInWindow.x - mouseDownLocation.x,
                event.locationInWindow.y - mouseDownLocation.y
            )
            guard delta >= Self.dragThreshold else { return }
            didStartDrag = true
            let dragEvent = mouseDownEvent ?? event
            mouseDownEvent = nil
            startFileDrag(with: dragEvent)
        }

        override func mouseUp(with event: NSEvent) {
            guard event.clickCount < 2, !didStartDrag else { return }
            mouseDownEvent = nil
            mouseUpAction?(event.modifierFlags)
        }

        override func rightMouseDown(with event: NSEvent) {
            mouseDownAction?(event.modifierFlags)
            super.rightMouseDown(with: event)
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            switch context {
            case .outsideApplication:
                return [.copy, .move, .generic]
            case .withinApplication:
                return [.copy, .move]
            @unknown default:
                return [.copy, .move]
            }
        }

        private func startFileDrag(with event: NSEvent) {
            guard let urls = dragURLsProvider?(), !urls.isEmpty else { return }

            onDragStarted?(urls)

            let draggingItems: [NSDraggingItem]
            if urls.count == 1 {
                let item = NSDraggingItem(pasteboardWriter: FileDragPasteboardWriter(url: urls[0]))
                let icon = NSWorkspace.shared.icon(forFile: urls[0].path)
                icon.size = NSSize(width: 32, height: 32)
                item.setDraggingFrame(
                    NSRect(origin: .zero, size: NSSize(width: 32, height: 32)),
                    contents: icon
                )
                draggingItems = [item]
            } else {
                let compositeImage = Self.compositeDragImage(
                    for: urls[0],
                    count: urls.count
                )
                draggingItems = urls.enumerated().map { index, url in
                    let item = NSDraggingItem(pasteboardWriter: FileDragPasteboardWriter(url: url))
                    let image = index == 0 ? compositeImage : Self.transparentDragImage()
                    let size = index == 0 ? compositeImage.size : NSSize(width: 1, height: 1)
                    item.setDraggingFrame(
                        NSRect(origin: NSPoint(x: index, y: -index), size: size),
                        contents: image
                    )
                    return item
                }
            }

            beginDraggingSession(with: draggingItems, event: event, source: self)
        }

        private static func transparentDragImage() -> NSImage {
            let image = NSImage(size: NSSize(width: 1, height: 1))
            image.lockFocus()
            NSColor.clear.setFill()
            NSRect(x: 0, y: 0, width: 1, height: 1).fill()
            image.unlockFocus()
            return image
        }

        private static func compositeDragImage(for url: URL, count: Int) -> NSImage {
            let iconSize: CGFloat = 32
            let badgeSize: CGFloat = 18
            let totalSize = NSSize(width: iconSize + 6, height: iconSize + 6)
            let image = NSImage(size: totalSize)

            image.lockFocus()
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.draw(
                in: NSRect(x: 0, y: 4, width: iconSize, height: iconSize),
                from: .zero,
                operation: .sourceOver,
                fraction: 1.0
            )

            let badgeRect = NSRect(
                x: totalSize.width - badgeSize,
                y: totalSize.height - badgeSize,
                width: badgeSize,
                height: badgeSize
            )
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: badgeRect).fill()

            let countStr = count > 99 ? "99+" : "\(count)"
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textSize = (countStr as NSString).size(withAttributes: attrs)
            let textPoint = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            (countStr as NSString).draw(at: textPoint, withAttributes: attrs)
            image.unlockFocus()

            return image
        }
    }
}

private struct LocalKeyDownMonitor: NSViewRepresentable {
    let isEnabled: Bool
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyDownMonitorView {
        let view = KeyDownMonitorView()
        view.isEnabled = isEnabled
        view.handle = handle
        return view
    }

    func updateNSView(_ nsView: KeyDownMonitorView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.handle = handle
    }

    static func dismantleNSView(_ nsView: KeyDownMonitorView, coordinator: ()) {
        nsView.stopMonitoring()
    }

    final class KeyDownMonitorView: NSView {
        var isEnabled = false
        var handle: ((NSEvent) -> Bool)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                stopMonitoring()
            } else {
                startMonitoringIfNeeded()
            }
        }

        func stopMonitoring() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

        private func startMonitoringIfNeeded() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      self.isEnabled,
                      self.window === event.window,
                      self.handle?(event) == true else {
                    return event
                }
                return nil
            }
        }
    }
}

private final class FileDragPasteboardWriter: NSObject, NSPasteboardWriting {
    private static let fileURLType = NSPasteboard.PasteboardType("public.file-url")
    private static let urlType = NSPasteboard.PasteboardType("public.url")
    private static let legacyFilenamesType = NSPasteboard.PasteboardType("NSFilenamesPboardType")

    private let url: URL

    init(url: URL) {
        self.url = url.standardizedFileURL
        super.init()
    }

    func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        [
            Self.fileURLType,
            Self.urlType,
            .string,
            Self.legacyFilenamesType
        ]
    }

    func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        switch type {
        case Self.fileURLType, Self.urlType:
            return url.absoluteString
        case .string:
            return url.path
        case Self.legacyFilenamesType:
            return [url.path]
        default:
            return nil
        }
    }

    func writingOptions(
        forType type: NSPasteboard.PasteboardType,
        pasteboard: NSPasteboard
    ) -> NSPasteboard.WritingOptions {
        []
    }
}

private struct FilePaneDropDelegate: DropDelegate {
    let side: PaneSide
    let model: DualFinderViewModel
    @Binding var isDropTargeted: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        isDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        isDropTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        if NSEvent.modifierFlags.contains(.option) {
            return DropProposal(operation: .copy)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        isDropTargeted = false
        let isCopy = NSEvent.modifierFlags.contains(.option)
        let providers = info.itemProviders(for: [.fileURL])
        let droppedURLs = DroppedURLAccumulator()
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let url = droppedFileURL(from: item) {
                    droppedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let uniqueURLs = Array(Set(droppedURLs.urls)).sorted { $0.path < $1.path }
            model.logDragDropEvent("drop.received", metadata: [
                "side": side.rawValue,
                "move": "\(!isCopy)",
                "count": "\(uniqueURLs.count)",
                "paths": uniqueURLs.map(\.path).joined(separator: "|")
            ])
            model.receiveDroppedFiles(uniqueURLs, into: side, move: !isCopy)
        }
        return true
    }
}

private func droppedFileURL(from item: NSSecureCoding?) -> URL? {
    if let data = item as? Data {
        if let url = URL(dataRepresentation: data, relativeTo: nil)?.standardizedFileURL {
            return url
        }
        if let string = String(data: data, encoding: .utf8),
           let url = URL(string: string)?.standardizedFileURL {
            return url
        }
    }
    if let url = item as? URL {
        return url.standardizedFileURL
    }
    if let nsURL = item as? NSURL, let url = nsURL.filePathURL?.standardizedFileURL {
        return url
    }
    return nil
}

private final class DroppedURLAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ url: URL) {
        lock.lock()
        storage.append(url)
        lock.unlock()
    }
}

private struct FileRow: View, Equatable {
    let item: FileItem
    let displayName: String
    let columnWidths: FileListColumnWidths
    let showsEncoding: Bool
    let isRenaming: Bool
    let isSelected: Bool
    let isActivePane: Bool
    let isVisuallyDeleted: Bool
    @Binding var renameText: String
    let commitRename: () -> Void
    let cancelRename: () -> Void

    nonisolated static func == (lhs: FileRow, rhs: FileRow) -> Bool {
        guard !lhs.isRenaming, !rhs.isRenaming else { return false }

        return lhs.item == rhs.item
            && lhs.displayName == rhs.displayName
            && lhs.columnWidths == rhs.columnWidths
            && lhs.showsEncoding == rhs.showsEncoding
            && lhs.isRenaming == rhs.isRenaming
            && lhs.isSelected == rhs.isSelected
            && lhs.isActivePane == rhs.isActivePane
            && lhs.isVisuallyDeleted == rhs.isVisuallyDeleted
    }

    var body: some View {
        HStack(spacing: FileListMetrics.iconColumnSpacing) {
            FinderFileIcon(url: item.url)
                .frame(width: FileListMetrics.iconColumnWidth)
            FileListColumnLayout(
                columnWidths: columnWidths,
                showsEncoding: showsEncoding,
                name: { nameView },
                type: {
                    Text(item.type)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                },
                encoding: {
                    Text(encodingText)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                },
                size: {
                    Text(sizeText)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                        .monospacedDigit()
                },
                modified: {
                    Text(dateText)
                        .font(.caption)
                        .foregroundStyle(secondaryTextColor)
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, FileListMetrics.horizontalPadding)
        .padding(.vertical, 2)
        .foregroundStyle(primaryTextColor)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 6)
                    .fill(rowSelectionBackgroundColor)
                    .padding(.vertical, 1)
            }
        }
        .overlay {
            if isRenaming {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                    .padding(.vertical, 1)
                    .allowsHitTesting(false)
            }
        }
        .opacity(isVisuallyDeleted ? 0.55 : 1)
        .overlay(alignment: .center) {
            if isVisuallyDeleted {
                Rectangle()
                    .fill(Color.red)
                    .frame(height: 2)
                    .padding(.horizontal, 2)
                .allowsHitTesting(false)
            }
        }
    }

    @ViewBuilder
    private var nameView: some View {
        if isRenaming {
            InlineRenameTextField(
                text: $renameText,
                item: item,
                commitRename: commitRename,
                cancelRename: cancelRename
            )
        } else {
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var primaryTextColor: Color {
        if isRenaming {
            return .primary
        }
        return isSelected && isActivePane ? Color.white : Color.primary
    }

    private var secondaryTextColor: Color {
        if isRenaming {
            return .secondary
        }
        return isSelected && isActivePane ? Color.white.opacity(0.86) : Color.secondary
    }

    private var rowSelectionBackgroundColor: Color {
        if isRenaming {
            return Color(nsColor: .textBackgroundColor)
        }
        return isActivePane ? Color.accentColor.opacity(0.88) : Color.secondary.opacity(0.24)
    }

    private var sizeText: String {
        FileSizeText.format(item.size)
    }

    private var encodingText: String {
        item.textEncoding ?? "--"
    }

    private var dateText: String {
        guard let modifiedAt = item.modifiedAt else { return "--" }
        return modifiedAt.formatted(date: .numeric, time: .shortened)
    }
}

private struct InlineRenameTextField: NSViewRepresentable {
    @Binding var text: String
    let item: FileItem
    let commitRename: () -> Void
    let cancelRename: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, commitRename: commitRename, cancelRename: cancelRename)
    }

    func makeNSView(context: Context) -> RenameNSTextField {
        let textField = RenameNSTextField()
        textField.isBordered = true
        textField.isBezeled = false
        textField.drawsBackground = true
        textField.backgroundColor = .textBackgroundColor
        textField.textColor = .labelColor
        textField.focusRingType = .none
        textField.usesSingleLineMode = true
        textField.cell?.isScrollable = true
        textField.delegate = context.coordinator
        textField.onCommit = { [weak textField, weak coordinator = context.coordinator] in
            if let textField {
                coordinator?.text.wrappedValue = textField.stringValue
            }
            coordinator?.commitRename()
        }
        textField.onCancel = { [weak coordinator = context.coordinator] in
            coordinator?.cancelRename()
        }
        return textField
    }

    func updateNSView(_ textField: RenameNSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.commitRename = commitRename
        context.coordinator.cancelRename = cancelRename
        if textField.stringValue != text {
            textField.stringValue = text
        }
        textField.backgroundColor = .textBackgroundColor
        textField.textColor = .labelColor
        textField.requestInitialSelection(initialSelectionRange)
    }

    private var initialSelectionRange: NSRange {
        let name = text as NSString
        guard !item.isDirectoryLike else {
            return NSRange(location: 0, length: name.length)
        }

        let baseName = name.deletingPathExtension as NSString
        guard !name.pathExtension.isEmpty, baseName.length > 0 else {
            return NSRange(location: 0, length: name.length)
        }
        return NSRange(location: 0, length: baseName.length)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var commitRename: () -> Void
        var cancelRename: () -> Void

        init(text: Binding<String>, commitRename: @escaping () -> Void, cancelRename: @escaping () -> Void) {
            self.text = text
            self.commitRename = commitRename
            self.cancelRename = cancelRename
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            text.wrappedValue = textField.stringValue
        }

        func control(
            _ control: NSControl,
            textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            switch commandSelector {
            case #selector(NSResponder.insertNewline(_:)):
                text.wrappedValue = textView.string
                commitRename()
                return true
            case #selector(NSResponder.cancelOperation(_:)):
                cancelRename()
                return true
            default:
                return false
            }
        }
    }
}

private final class RenameNSTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    private var pendingInitialSelection: NSRange?
    private var didApplyInitialSelection = false

    func requestInitialSelection(_ range: NSRange) {
        guard !didApplyInitialSelection else { return }
        pendingInitialSelection = range
        applyPendingInitialSelection()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyPendingInitialSelection()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76:
            onCommit?()
        case 53:
            onCancel?()
        default:
            super.keyDown(with: event)
        }
    }

    private func applyPendingInitialSelection() {
        guard let window, let range = pendingInitialSelection, !didApplyInitialSelection else {
            return
        }

        didApplyInitialSelection = true
        pendingInitialSelection = nil
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            window.makeFirstResponder(self)
            DispatchQueue.main.async { [weak self] in
                guard let self, let editor = self.currentEditor() else { return }
                editor.selectedRange = range
            }
        }
    }
}

private struct SortHeaderButton: View {
    let title: String
    let field: FileSortField
    let rule: FileSortRule
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: iconName)
                    .font(.caption2)
                    .opacity(rule.field == field ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var iconName: String {
        rule.direction == .ascending ? "chevron.up" : "chevron.down"
    }

    private var alignment: Alignment {
        field == .size || field == .modifiedAt ? .trailing : .leading
    }

    private var helpText: String {
        "Sort by \(title)"
    }
}
