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
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
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
                                            doubleClick: {
                                                activateItem(item.url)
                                            }
                                        )
                                    }
                                }
                                .onDrag {
                                    let urls = dragURLs(startingWith: item.url)
                                    return NSItemProvider(object: urls.first! as NSURL)
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
                        Button("Copy Absolute Path") { model.copyAbsolutePaths(selection, on: side) }
                        Button("Open in Ghostty or Terminal") { model.openInTerminal(selection, on: side) }
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
                    .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                        receiveDrop(providers)
                    }
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
            SortHeaderButton(title: "Name", field: .name, rule: model.sortRule(for: side)) {
                model.selectSortField(.name, for: side)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SortHeaderButton(title: "Type", field: .type, rule: model.sortRule(for: side)) {
                model.selectSortField(.type, for: side)
            }
            .frame(width: 112, alignment: .leading)
            SortHeaderButton(title: "Size", field: .size, rule: model.sortRule(for: side)) {
                model.selectSortField(.size, for: side)
            }
            .frame(width: 86, alignment: .trailing)
            SortHeaderButton(title: "Modified", field: .modifiedAt, rule: model.sortRule(for: side)) {
                model.selectSortField(.modifiedAt, for: side)
            }
            .frame(width: 126, alignment: .trailing)
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
        clearRenameState()
        model.renameItem(renamingURL, to: newName, on: side)
        restoreFileListFocus()
    }

    private func cancelRename() {
        clearRenameState()
        restoreFileListFocus()
    }

    private func clearRenameState() {
        renamingURL = nil
        pendingRenameURL = nil
        pendingRevealURL = nil
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

        model.selectItem(url, on: side)
    }

    private func dragURLs(startingWith url: URL) -> [URL] {
        let selection = model.pane(for: side).selectedItemURLs
        guard selection.contains(url) else { return [url] }
        let orderedSelection = model.items(for: side).map(\.url).filter { selection.contains($0) }
        return orderedSelection.isEmpty ? [url] : orderedSelection
    }

    private func receiveDrop(_ providers: [NSItemProvider]) -> Bool {
        let move = NSEvent.modifierFlags.contains(.command)
        let droppedURLs = DroppedURLAccumulator()
        let group = DispatchGroup()

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                if let data = item as? Data,
                   let url = URL(dataRepresentation: data, relativeTo: nil)?.standardizedFileURL {
                    droppedURLs.append(url)
                } else if let url = item as? URL {
                    droppedURLs.append(url.standardizedFileURL)
                } else if let nsURL = item as? NSURL,
                          let url = nsURL.filePathURL?.standardizedFileURL {
                    droppedURLs.append(url)
                }
            }
        }

        group.notify(queue: .main) {
            let uniqueURLs = Array(Set(droppedURLs.urls)).sorted { $0.path < $1.path }
            model.receiveDroppedFiles(uniqueURLs, into: side, move: move)
        }
        return true
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
    let doubleClick: () -> Void

    func makeNSView(context: Context) -> MouseHandlingView {
        let view = MouseHandlingView()
        view.mouseDownAction = mouseDown
        view.doubleClickAction = doubleClick
        return view
    }

    func updateNSView(_ nsView: MouseHandlingView, context: Context) {
        nsView.mouseDownAction = mouseDown
        nsView.doubleClickAction = doubleClick
    }

    final class MouseHandlingView: NSView {
        var mouseDownAction: ((NSEvent.ModifierFlags) -> Void)?
        var doubleClickAction: (() -> Void)?

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
                mouseDownAction?(event.modifierFlags)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            mouseDownAction?(event.modifierFlags)
            super.rightMouseDown(with: event)
        }
    }
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
    let isRenaming: Bool
    @Binding var renameText: String
    let commitRename: () -> Void
    let cancelRename: () -> Void
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(item.isDirectoryLike ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            nameView
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.type)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 112, alignment: .leading)
            Text(sizeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 86, alignment: .trailing)
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 126, alignment: .trailing)
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

    private var iconName: String {
        switch item.kind {
        case .folder: "folder"
        case .package: "shippingbox"
        case .alias: "arrowshape.turn.up.right"
        case .file, .other: "doc"
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
