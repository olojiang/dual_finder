import AppKit
import SwiftUI
import DualFinderCore
import UniformTypeIdentifiers

struct FilePaneView: View {
    let side: PaneSide
    @ObservedObject var model: DualFinderViewModel
    @State private var renamingURL: URL?
    @State private var pendingRenameURL: URL?
    @State private var pendingRevealURL: URL?
    @State private var pendingNewFolderMoveSources: [URL]?
    @State private var renameText = ""
    @State private var isEditingPath = false
    @State private var pathText = ""
    @State private var isFileSearchPresented = false
    @State private var fileSearchQuery = ""
    @State private var isDropTargeted = false
    @FocusState private var isFileListFocused: Bool
    @FocusState private var isPathFieldFocused: Bool
    @FocusState private var isFileSearchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            tabStrip
            fileList
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
                pathText = url.path
            }
            dismissFileSearch(restoreFocus: false)
        }
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
            pathControl
            IconButton(systemName: "plus.square.on.square", help: "New tab") {
                model.addTab(on: side)
            }
            IconButton(systemName: "xmark.square", help: "Close tab") {
                model.closeSelectedTab(on: side)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
            Text(model.pane(for: side).selectedURL.path)
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
                            Text(tab.url.lastPathComponent.isEmpty ? tab.url.path : tab.url.lastPathComponent)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tab.id == model.pane(for: side).selectedTabID ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(tab.url.path)
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

    @ViewBuilder
    private func finderStyleContextMenuItems(for selection: Set<URL>) -> some View {
        let ordered = model.orderedContextMenuURLs(selection, on: side)

        if model.canCreateFolderWithSelection(selection) {
            Button(newFolderWithSelectionTitle(selection.count)) {
                beginNewFolderWithSelection(ordered)
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
    private func pathAndTerminalContextMenuItems(for urls: Set<URL>, selectTabID: UUID? = nil) -> some View {
        Button("Copy Absolute Path") {
            if let selectTabID {
                model.selectTab(selectTabID, on: side)
            }
            model.copyAbsolutePaths(urls, on: side)
        }
        Button("Open in Ghostty or Terminal") {
            if let selectTabID {
                model.selectTab(selectTabID, on: side)
            }
            model.openInTerminal(urls, on: side)
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
        VStack(spacing: 0) {
            sortHeader
            ZStack(alignment: .top) {
                ScrollViewReader { scrollProxy in
                    List(selection: model.bindingForSelection(side: side)) {
                        ForEach(visibleItems) { item in
                            FileRow(
                                item: item,
                                columnWidths: model.uiLayoutPreferences.columnWidths,
                                isRenaming: renamingURL == item.url,
                                renameText: $renameText,
                                commitRename: commitRename,
                                cancelRename: cancelRename
                            )
                                .id(item.url)
                                .tag(item.url)
                                .contentShape(Rectangle())
                                .overlay {
                                    if renamingURL != item.url {
                                        RowMouseHandler(
                                            mouseDown: { modifierFlags in
                                                selectItemFromRowMouseDown(item.url, modifierFlags: modifierFlags)
                                            },
                                            mouseUp: { modifierFlags in
                                                selectItemFromRowMouseUp(item.url, modifierFlags: modifierFlags)
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
                    .focused($isFileListFocused)
                    .onChange(of: isFileListFocused) { _, isFocused in
                        model.logPaneFocusEvent("file-list.focus-state.changed", metadata: [
                            "side": side.rawValue,
                            "focused": "\(isFocused)"
                        ])
                    }
                    .onKeyPress(.escape, phases: .down) { _ in
                        guard isFileSearchPresented, renamingURL == nil else { return .ignored }
                        dismissFileSearch()
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
                            model.trashSelection(from: side)
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
                    .contextMenu(forSelectionType: URL.self) { selection in
                        finderStyleContextMenuItems(for: selection)
                        Divider()
                        pathAndTerminalContextMenuItems(for: selection)
                        archiveContextMenuItems(for: selection)
                        favoriteContextMenuItems(for: selection)
                        Divider()
                        Button("Batch Rename...") { model.requestBatchRenameDialog(on: side) }
                        Button("Copy to Other Pane") { model.copySelection(from: side) }
                        Button("Move to Other Pane") { model.moveSelection(from: side) }
                        Button("Move to Trash", role: .destructive) { model.trashSelection(from: side) }
                    } primaryAction: { selection in
                        model.activateFirstItem(in: selection, on: side)
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
                                model.trashSelection(from: side)
                            }
                            IconButton(systemName: "arrow.clockwise", help: "Refresh pane") {
                                model.refresh(side)
                            }
                            IconButton(systemName: "ruler", help: "Calculate selected folder size (Ctrl-Space)") {
                                model.calculateSelectedFolderSizes(on: side)
                            }
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
                        revealPendingItemIfReady(with: scrollProxy)
                        synchronizeFileSearchSelection()
                    }
                    .onChange(of: fileSearchQuery) { _, _ in
                        synchronizeFileSearchSelection()
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
                        .padding(.top, 8)
                        .padding(.horizontal, 24)
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

    private var visibleItems: [FileItem] {
        let allItems = model.items(for: side)
        guard isFileSearchPresented else { return allItems }

        let query = fileSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return allItems }

        return allItems.filter { item in
            FileNameSearch.matches(item.name, query: query)
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

        return HStack(spacing: 12) {
            summaryMetric("Files", value: "\(summary.fileCount)")
            summaryMetric("Size", value: summary.formattedFileSize)
            summaryMetric("Folders", value: "\(summary.folderCount)")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .accessibilityLabel("Files \(summary.fileCount), total size \(summary.formattedFileSize), folders \(summary.folderCount)")
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
        HStack(spacing: 8) {
            Color.clear.frame(width: 20)
            FileListColumnLayout(
                columnWidths: model.uiLayoutPreferences.columnWidths,
                showsResizeHandles: true,
                onResizeColumn: { column, delta in
                    model.adjustFileListColumn(column, by: delta)
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
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.bar)
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

    private func moveFileSearchSelection(_ delta: Int) {
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
        isFileSearchPresented = false
        fileSearchQuery = ""
        isFileSearchFocused = false
        model.logFileSearchEvent("dismissed", metadata: [
            "side": side.rawValue
        ])
        if restoreFocus {
            restoreFileListFocus()
        }
    }

    private func dismissPathEditingForFileSearch() {
        guard isEditingPath else { return }
        isEditingPath = false
        pathText = model.pane(for: side).selectedURL.path
        isPathFieldFocused = false
    }

    private func isControlOnly(_ modifiers: EventModifiers) -> Bool {
        modifiers.contains(.control)
            && !modifiers.contains(.command)
            && !modifiers.contains(.option)
            && !modifiers.contains(.shift)
    }

    private func beginRenaming(_ url: URL) {
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
              model.items(for: side).contains(where: { $0.url == pendingRenameURL }) else {
            return
        }
        self.pendingRenameURL = nil
        beginRenaming(pendingRenameURL)
    }

    private func revealPendingItemIfReady(with scrollProxy: ScrollViewProxy) {
        guard let url = pendingRevealURL,
              model.items(for: side).contains(where: { $0.url == url }) else {
            return
        }

        pendingRevealURL = nil
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                scrollProxy.scrollTo(url, anchor: .center)
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
        model.renameItem(renamingURL, to: newName, on: side)
        restoreFileListFocus()
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
        pathText = model.pane(for: side).selectedURL.path
        restoreFileListFocus()
    }

    private func cancelPathEditing() {
        isEditingPath = false
        pathText = model.pane(for: side).selectedURL.path
        restoreFileListFocus()
    }

    private func activateItem(_ url: URL) {
        guard renamingURL == nil else { return }
        model.activateItem(url, on: side)
        restoreFileListFocus()
    }

    private func selectItemFromRowMouseDown(_ url: URL, modifierFlags: NSEvent.ModifierFlags) {
        guard renamingURL == nil else { return }

        isFileListFocused = true
        model.activatePane(side)

        if modifierFlags.contains(.command) {
            model.toggleItemSelection(url, on: side)
            return
        }

        if modifierFlags.contains(.shift) {
            model.extendSelection(to: url, on: side)
            return
        }

        let currentSelection = model.pane(for: side).selectedItemURLs
        if currentSelection.contains(url) {
            return
        }

        model.selectItem(url, on: side)
    }

    private func selectItemFromRowMouseUp(_ url: URL, modifierFlags: NSEvent.ModifierFlags) {
        guard renamingURL == nil else { return }
        guard !modifierFlags.contains(.command), !modifierFlags.contains(.shift) else { return }

        let selection = model.pane(for: side).selectedItemURLs
        guard selection.contains(url), selection.count > 1 else { return }
        model.selectItem(url, on: side)
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
            isFileListFocused = true
            guard let requestID else { return }
            var metadata = [
                "requestID": requestID,
                "side": side.rawValue
            ]
            if let reason {
                metadata["reason"] = reason
            }
            if let revealURL {
                metadata["revealPath"] = revealURL.path
            }
            model.logPaneFocusEvent("file-list.focus-set.requested", metadata: metadata)
        }
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

private struct FileRow: View {
    let item: FileItem
    let columnWidths: FileListColumnWidths
    let isRenaming: Bool
    @Binding var renameText: String
    let commitRename: () -> Void
    let cancelRename: () -> Void
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            FinderFileIcon(url: item.url)
                .frame(width: 20)
            FileListColumnLayout(
                columnWidths: columnWidths,
                name: { nameView },
                type: {
                    Text(item.type)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                },
                size: {
                    Text(sizeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                },
                modified: {
                    Text(dateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var nameView: some View {
        if isRenaming {
            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .focused($isRenameFocused)
                .onSubmit(commitRename)
                .onKeyPress(.escape, phases: .down) { _ in
                    cancelRename()
                    return .handled
                }
                .onAppear {
                    isRenameFocused = true
                    DispatchQueue.main.async {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                }
        } else {
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var sizeText: String {
        guard let size = item.size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var dateText: String {
        guard let modifiedAt = item.modifiedAt else { return "--" }
        return modifiedAt.formatted(date: .numeric, time: .shortened)
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
