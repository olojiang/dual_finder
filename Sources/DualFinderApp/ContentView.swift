import AppKit
import SwiftUI
import DualFinderCore

struct ContentView: View {
    @ObservedObject var model: DualFinderViewModel

    var body: some View {
        VStack(spacing: 0) {
            AppToolbar(model: model)
            Divider()
            HStack(spacing: 0) {
                FilePaneView(side: .left, model: model)
                Divider()
                FilePaneView(side: .right, model: model)
            }
            Divider()
            OperationQueueBar(model: model)
            StatusBar(message: model.statusMessage)
        }
        .background(.background)
        .background(AppShortcutHandler {
            model.requestPathEditing(on: model.activePaneSide)
        } showFileSearch: {
            model.requestFileSearch(on: model.activePaneSide)
        } showFolderBookmarks: {
            model.requestFolderBookmarkDialog(on: model.activePaneSide)
        } showBatchRename: {
            model.requestBatchRenameDialog(on: model.activePaneSide)
        } focusPane: { side, requestID in
            model.requestPaneFocus(side, requestID: requestID, source: "cmd-arrow")
        } selectTab: { index, requestID in
            let side = model.activePaneSide
            if model.selectTab(atZeroBasedIndex: index, on: side, requestID: requestID, source: "cmd-number") {
                model.requestPaneFocus(side, requestID: requestID, source: "cmd-number")
            }
        } logShortcutEvent: { message, metadata in
            model.logShortcutEvent(message, metadata: metadata)
        } navigateBack: {
            model.navigateBack(model.activePaneSide)
        } navigateForward: {
            model.navigateForward(model.activePaneSide)
        } moveLeftSelectionToRight: {
            model.moveSelection(from: .left)
        } moveRightSelectionToLeft: {
            model.moveSelection(from: .right)
        })
        .sheet(item: $model.folderBookmarkDialogRequest) { _ in
            FolderBookmarkDialog(model: model)
        }
        .sheet(item: $model.batchRenameDialogRequest) { request in
            BatchRenameDialog(model: model, side: request.side)
        }
        .sheet(item: $model.fileConflictDialogRequest) { request in
            FileConflictDialog(model: model, request: request)
        }
        .sheet(item: $model.directoryComparisonDialogRequest) { _ in
            DirectoryComparisonDialog(model: model)
        }
        .sheet(item: $model.globalSearchDialogRequest) { _ in
            GlobalSearchDialog(model: model)
        }
        .alert(item: $model.diskAccessPrompt) { prompt in
            Alert(
                title: Text("Full Disk Access Required"),
                message: Text("\(prompt.message)\n\nBlocked path: \(prompt.path)"),
                primaryButton: .default(Text("Open Settings")) {
                    model.openFullDiskAccessSettings()
                },
                secondaryButton: .cancel(Text("Later")) {
                    model.dismissDiskAccessPrompt()
                }
            )
        }
    }
}

private struct OperationQueueBar: View {
    @ObservedObject var model: DualFinderViewModel

    private var visibleOperations: [QueuedFileOperation] {
        Array(model.fileOperationQueue
            .filter { $0.status == .queued || $0.status == .running }
            .suffix(3))
    }

    var body: some View {
        if !visibleOperations.isEmpty {
            VStack(spacing: 0) {
                ForEach(visibleOperations) { operation in
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: operation.kind))
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(operation.title)
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                Text(operation.message)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            ProgressView(value: operation.fractionCompleted ?? 0)
                                .progressViewStyle(.linear)
                        }
                        IconButton(systemName: "xmark.circle", help: "Cancel operation") {
                            model.cancelFileOperation(operation.id)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                }
            }
            .background(.bar)
            Divider()
        }
    }

    private func iconName(for kind: QueuedFileOperationKind) -> String {
        switch kind {
        case .copy: "doc.on.doc"
        case .move: "arrow.right.doc.on.clipboard"
        case .trash: "trash"
        }
    }
}

private struct FileConflictDialog: View {
    @ObservedObject var model: DualFinderViewModel
    let request: FileConflictDialogRequest
    @State private var applyToAll = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text("File Already Exists")
                    .font(.headline)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(request.destination.lastPathComponent)
                    .font(.body)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(request.destination.deletingLastPathComponent().path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Toggle("Apply to all conflicts", isOn: $applyToAll)
            HStack {
                Button("Skip") {
                    model.resolveFileConflict(.skip, applyToAll: applyToAll)
                }
                Spacer()
                Button("Keep Both") {
                    model.resolveFileConflict(.keepBoth, applyToAll: applyToAll)
                }
                Button("Overwrite", role: .destructive) {
                    model.resolveFileConflict(.overwrite, applyToAll: applyToAll)
                }
            }
        }
        .padding(18)
        .frame(width: 420)
    }
}

private struct DirectoryComparisonDialog: View {
    @ObservedObject var model: DualFinderViewModel
    @Environment(\.dismiss) private var dismiss

    private var differences: [DirectoryComparisonEntry] {
        model.directoryComparisonResults.filter { $0.status != .same }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Directory Compare")
                    .font(.headline)
                Spacer()
                IconButton(systemName: "arrow.clockwise", help: "Refresh comparison") {
                    model.compareDirectories()
                }
                IconButton(systemName: "xmark", help: "Close") {
                    dismiss()
                }
            }
            HStack {
                Text(model.leftPane.selectedURL.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(model.rightPane.selectedURL.path)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)

            if differences.isEmpty {
                ContentUnavailableView("Folders match", systemImage: "checkmark.circle")
                    .frame(height: 320)
            } else {
                List(differences) { entry in
                    HStack(spacing: 10) {
                        Image(systemName: iconName(for: entry.status))
                            .foregroundStyle(color(for: entry.status))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.relativePath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(entry.status.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.syncComparisonEntry(entry, direction: .left)
                        } label: {
                            Image(systemName: "arrow.left")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy right item to left")
                        .disabled(entry.rightURL == nil)
                        Button {
                            model.syncComparisonEntry(entry, direction: .right)
                        } label: {
                            Image(systemName: "arrow.right")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy left item to right")
                        .disabled(entry.leftURL == nil)
                    }
                }
                .frame(height: 360)
            }
        }
        .padding(16)
        .frame(width: 720)
    }

    private func iconName(for status: DirectoryComparisonStatus) -> String {
        switch status {
        case .onlyLeft: "arrow.left.circle"
        case .onlyRight: "arrow.right.circle"
        case .different: "exclamationmark.circle"
        case .same: "checkmark.circle"
        }
    }

    private func color(for status: DirectoryComparisonStatus) -> Color {
        switch status {
        case .onlyLeft, .onlyRight: .accentColor
        case .different: .orange
        case .same: .green
        }
    }
}

private struct GlobalSearchDialog: View {
    @ObservedObject var model: DualFinderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var searchContents = false
    @FocusState private var isQueryFocused: Bool

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Recursive Search")
                    .font(.headline)
                Spacer()
                IconButton(systemName: "xmark", help: "Close") {
                    dismiss()
                }
            }
            HStack(spacing: 8) {
                TextField("Search names or contents", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($isQueryFocused)
                    .onSubmit(runSearch)
                Toggle("Contents", isOn: $searchContents)
                Button(model.isGlobalSearchRunning ? "Cancel" : "Search") {
                    model.isGlobalSearchRunning ? model.cancelGlobalSearch() : runSearch()
                }
                .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if model.globalSearchResults.isEmpty {
                ContentUnavailableView(
                    model.isGlobalSearchRunning ? "Searching..." : "No results",
                    systemImage: model.isGlobalSearchRunning ? "magnifyingglass" : "doc.text.magnifyingglass"
                )
                .frame(height: 340)
            } else {
                List(model.globalSearchResults) { result in
                    HStack(spacing: 8) {
                        Image(systemName: result.matchedContent ? "text.page" : "doc")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(result.url.lastPathComponent)
                                .lineLimit(1)
                            Text(result.url.deletingLastPathComponent().path)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.revealSearchResult(result)
                        dismiss()
                    }
                }
                .frame(height: 340)
            }
        }
        .padding(16)
        .frame(width: 680)
        .onAppear {
            isQueryFocused = true
        }
    }

    private func runSearch() {
        model.startGlobalSearch(query: query, searchContents: searchContents)
    }
}

private struct AppShortcutHandler: NSViewRepresentable {
    let goToFolder: () -> Void
    let showFileSearch: () -> Void
    let showFolderBookmarks: () -> Void
    let showBatchRename: () -> Void
    let focusPane: (PaneSide, String) -> Void
    let selectTab: (Int, String) -> Void
    let logShortcutEvent: (String, [String: String]) -> Void
    let navigateBack: () -> Void
    let navigateForward: () -> Void
    let moveLeftSelectionToRight: () -> Void
    let moveRightSelectionToLeft: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            goToFolder: goToFolder,
            showFileSearch: showFileSearch,
            showFolderBookmarks: showFolderBookmarks,
            showBatchRename: showBatchRename,
            focusPane: focusPane,
            selectTab: selectTab,
            logShortcutEvent: logShortcutEvent,
            navigateBack: navigateBack,
            navigateForward: navigateForward,
            moveLeftSelectionToRight: moveLeftSelectionToRight,
            moveRightSelectionToLeft: moveRightSelectionToLeft
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.goToFolder = goToFolder
        context.coordinator.showFileSearch = showFileSearch
        context.coordinator.showFolderBookmarks = showFolderBookmarks
        context.coordinator.showBatchRename = showBatchRename
        context.coordinator.focusPane = focusPane
        context.coordinator.selectTab = selectTab
        context.coordinator.logShortcutEvent = logShortcutEvent
        context.coordinator.navigateBack = navigateBack
        context.coordinator.navigateForward = navigateForward
        context.coordinator.moveLeftSelectionToRight = moveLeftSelectionToRight
        context.coordinator.moveRightSelectionToLeft = moveRightSelectionToLeft
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var goToFolder: () -> Void
        var showFileSearch: () -> Void
        var showFolderBookmarks: () -> Void
        var showBatchRename: () -> Void
        var focusPane: (PaneSide, String) -> Void
        var selectTab: (Int, String) -> Void
        var logShortcutEvent: (String, [String: String]) -> Void
        var navigateBack: () -> Void
        var navigateForward: () -> Void
        var moveLeftSelectionToRight: () -> Void
        var moveRightSelectionToLeft: () -> Void
        private var monitor: Any?

        init(
            goToFolder: @escaping () -> Void,
            showFileSearch: @escaping () -> Void,
            showFolderBookmarks: @escaping () -> Void,
            showBatchRename: @escaping () -> Void,
            focusPane: @escaping (PaneSide, String) -> Void,
            selectTab: @escaping (Int, String) -> Void,
            logShortcutEvent: @escaping (String, [String: String]) -> Void,
            navigateBack: @escaping () -> Void,
            navigateForward: @escaping () -> Void,
            moveLeftSelectionToRight: @escaping () -> Void,
            moveRightSelectionToLeft: @escaping () -> Void
        ) {
            self.goToFolder = goToFolder
            self.showFileSearch = showFileSearch
            self.showFolderBookmarks = showFolderBookmarks
            self.showBatchRename = showBatchRename
            self.focusPane = focusPane
            self.selectTab = selectTab
            self.logShortcutEvent = logShortcutEvent
            self.navigateBack = navigateBack
            self.navigateForward = navigateForward
            self.moveLeftSelectionToRight = moveLeftSelectionToRight
            self.moveRightSelectionToLeft = moveRightSelectionToLeft
        }

        func install() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if Self.isGoToFolderShortcut(event) {
                    self?.goToFolder()
                    return nil
                }

                if Self.isFileSearchShortcut(event) {
                    self?.showFileSearch()
                    return nil
                }

                if Self.isFolderBookmarksShortcut(event) {
                    self?.showFolderBookmarks()
                    return nil
                }

                if Self.isBatchRenameShortcut(event) {
                    self?.showBatchRename()
                    return nil
                }

                if Self.isFocusLeftPaneShortcut(event) {
                    self?.handlePaneFocusShortcut(event, target: .left)
                    return nil
                }

                if Self.isFocusRightPaneShortcut(event) {
                    self?.handlePaneFocusShortcut(event, target: .right)
                    return nil
                }

                if let tabIndex = Self.tabShortcutIndex(event) {
                    self?.handleTabSelectionShortcut(event, index: tabIndex)
                    return nil
                }

                if Self.isNavigateBackShortcut(event) {
                    self?.navigateBack()
                    return nil
                }

                if Self.isNavigateForwardShortcut(event) {
                    self?.navigateForward()
                    return nil
                }

                if Self.isMoveLeftSelectionToRightShortcut(event) {
                    self?.moveLeftSelectionToRight()
                    return nil
                }

                if Self.isMoveRightSelectionToLeftShortcut(event) {
                    self?.moveRightSelectionToLeft()
                    return nil
                }

                return event
            }
        }

        private func handlePaneFocusShortcut(_ event: NSEvent, target: PaneSide) {
            let requestID = UUID().uuidString
            logShortcutEvent("key-down", [
                "requestID": requestID,
                "target": target.rawValue,
                "keyCode": "\(event.keyCode)",
                "characters": event.charactersIgnoringModifiers ?? "",
                "modifiers": Self.modifierDescription(for: event),
                "rawModifierFlags": "\(event.modifierFlags.rawValue)"
            ])
            focusPane(target, requestID)
        }

        private func handleTabSelectionShortcut(_ event: NSEvent, index: Int) {
            let requestID = UUID().uuidString
            logShortcutEvent("key-down", [
                "requestID": requestID,
                "target": "active-pane-tab",
                "displayIndex": "\(index + 1)",
                "keyCode": "\(event.keyCode)",
                "characters": event.charactersIgnoringModifiers ?? "",
                "modifiers": Self.modifierDescription(for: event)
            ])
            selectTab(index, requestID)
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        deinit {
            remove()
        }

        private static func isGoToFolderShortcut(_ event: NSEvent) -> Bool {
            let flags = shortcutModifierFlags(for: event)
            return flags == [.command, .shift]
                && event.charactersIgnoringModifiers?.lowercased() == "g"
        }

        private static func isFolderBookmarksShortcut(_ event: NSEvent) -> Bool {
            let flags = shortcutModifierFlags(for: event)
            return flags == .control
                && event.charactersIgnoringModifiers?.lowercased() == "d"
        }

        private static func isFileSearchShortcut(_ event: NSEvent) -> Bool {
            isControlShortcut(event, character: "s", keyCode: 1)
        }

        private static func isBatchRenameShortcut(_ event: NSEvent) -> Bool {
            let flags = shortcutModifierFlags(for: event)
            return flags == .control
                && event.charactersIgnoringModifiers?.lowercased() == "m"
        }

        private static func isNavigateBackShortcut(_ event: NSEvent) -> Bool {
            isControlShortcut(event, character: "[", keyCode: 33)
        }

        private static func isNavigateForwardShortcut(_ event: NSEvent) -> Bool {
            isControlShortcut(event, character: "]", keyCode: 30)
        }

        private static func isFocusLeftPaneShortcut(_ event: NSEvent) -> Bool {
            isCommandArrowShortcut(event, keyCode: 123)
        }

        private static func isFocusRightPaneShortcut(_ event: NSEvent) -> Bool {
            isCommandArrowShortcut(event, keyCode: 124)
        }

        private static func tabShortcutIndex(_ event: NSEvent) -> Int? {
            let flags = shortcutModifierFlags(for: event)
            guard flags == .command,
                  let character = event.charactersIgnoringModifiers,
                  character.count == 1,
                  let number = Int(character),
                  (1...9).contains(number)
            else {
                return nil
            }
            return number - 1
        }

        private static func isMoveLeftSelectionToRightShortcut(_ event: NSEvent) -> Bool {
            isCommandOptionArrowShortcut(event, keyCode: 124)
        }

        private static func isMoveRightSelectionToLeftShortcut(_ event: NSEvent) -> Bool {
            isCommandOptionArrowShortcut(event, keyCode: 123)
        }

        private static func isControlShortcut(_ event: NSEvent, character: String, keyCode: UInt16) -> Bool {
            let flags = shortcutModifierFlags(for: event)
            return flags == .control
                && (event.charactersIgnoringModifiers == character || event.keyCode == keyCode)
        }

        private static func isCommandOptionArrowShortcut(_ event: NSEvent, keyCode: UInt16) -> Bool {
            let flags = shortcutModifierFlags(for: event)
            return flags == [.command, .option] && event.keyCode == keyCode
        }

        private static func isCommandArrowShortcut(_ event: NSEvent, keyCode: UInt16) -> Bool {
            let flags = shortcutModifierFlags(for: event)
            return flags == .command && event.keyCode == keyCode
        }

        private static func shortcutModifierFlags(for event: NSEvent) -> NSEvent.ModifierFlags {
            event.modifierFlags.intersection([.command, .option, .control, .shift])
        }

        private static func modifierDescription(for event: NSEvent) -> String {
            let flags = shortcutModifierFlags(for: event)
            var names: [String] = []
            if flags.contains(.command) { names.append("command") }
            if flags.contains(.option) { names.append("option") }
            if flags.contains(.control) { names.append("control") }
            if flags.contains(.shift) { names.append("shift") }
            return names.joined(separator: "+")
        }
    }
}

private struct FolderBookmarkDialog: View {
    @ObservedObject var model: DualFinderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var entries: [FolderBookmarkEntry] = []
    @State private var selectedIndex = 0
    @State private var isListSelectionActive = false
    @FocusState private var isSearchFocused: Bool

    private var filteredEntries: [FolderBookmarkEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return entries }

        let needle = trimmedQuery.localizedLowercase
        return entries.filter { entry in
            entry.url.path.localizedLowercase.contains(needle)
                || entry.url.lastPathComponent.localizedLowercase.contains(needle)
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("Folder Favorites")
                    .font(.headline)
                Spacer()
                IconButton(systemName: "xmark", help: "Cancel") {
                    dismiss()
                }
            }

            TextField("Search folders", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($isSearchFocused)
                .onSubmit {
                    logDialogEvent("search.submit", metadata: [
                        "query": query,
                        "filteredCount": "\(filteredEntries.count)",
                        "selectedIndex": "\(selectedIndex)"
                    ])
                    beginListSelection()
                }
                .onKeyPress(KeyEquivalent("m"), phases: .down) { keyPress in
                    guard keyPress.modifiers.contains(.control) else { return .ignored }
                    addCurrentFolder()
                    return .handled
                }
                .onKeyPress(KeyEquivalent("r"), phases: .down) { keyPress in
                    guard keyPress.modifiers.contains(.control) else { return .ignored }
                    removeSelectedFavorite()
                    return .handled
                }

            Group {
                if filteredEntries.isEmpty {
                    ContentUnavailableView("No matching folders", systemImage: "folder.badge.questionmark")
                        .frame(height: 260)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 2) {
                                ForEach(Array(filteredEntries.enumerated()), id: \.element.id) { index, entry in
                                    FolderBookmarkRow(
                                        entry: entry,
                                        isSelected: index == selectedIndex
                                    )
                                    .id(entry.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedIndex = index
                                        beginListSelection()
                                    }
                                    .onTapGesture(count: 2) {
                                        selectedIndex = index
                                        confirmSelection()
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .frame(height: 260)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onChange(of: selectedIndex) { _, index in
                            guard filteredEntries.indices.contains(index) else { return }
                            proxy.scrollTo(filteredEntries[index].id, anchor: .center)
                        }
                    }
                }
            }
            .focusable()
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { keyPress in
                guard keyPress.modifiers.isEmpty else { return .ignored }
                guard isListSelectionActive else { return .ignored }
                moveSelection(keyPress.key == .upArrow ? -1 : 1)
                return .handled
            }
            .onKeyPress(.return, phases: .down) { _ in
                guard isListSelectionActive else { return .ignored }
                confirmSelection()
                return .handled
            }
            .onKeyPress(.escape, phases: .down) { _ in
                dismiss()
                return .handled
            }

            HStack {
                Button("Add Current (Ctrl-M)") {
                    addCurrentFolder()
                }
                Button("Remove Favorite (Ctrl-R)") {
                    removeSelectedFavorite()
                }
                .disabled(!selectedEntryIsFavorite)
                Spacer()
                Button("Cancel", role: .cancel) {
                    dismiss()
                }
                Button("Open") {
                    confirmSelection()
                }
                .buttonStyle(.borderedProminent)
                .disabled(filteredEntries.isEmpty)
            }
        }
        .padding(16)
        .frame(width: 560)
        .background(
            FolderBookmarkDialogKeyHandler(
                isListSelectionActive: isListSelectionActive,
                moveSelection: moveSelection,
                beginListSelection: beginListSelection,
                confirmSelection: confirmSelection,
                cancel: dismiss.callAsFunction,
                addCurrentFolder: addCurrentFolder,
                removeSelectedFavorite: removeSelectedFavorite,
                focusSearch: focusSearch,
                logEvent: logDialogEvent
            )
        )
        .onAppear {
            reloadEntries()
            isSearchFocused = true
            logDialogEvent("appeared", metadata: [
                "entries": "\(entries.count)",
                "filteredCount": "\(filteredEntries.count)",
                "selectedIndex": "\(selectedIndex)"
            ])
        }
        .onChange(of: query) { _, _ in
            clampSelection()
            isListSelectionActive = false
            isSearchFocused = true
            logDialogEvent("query.changed", metadata: [
                "query": query,
                "filteredCount": "\(filteredEntries.count)",
                "selectedIndex": "\(selectedIndex)"
            ])
        }
    }

    private var selectedEntry: FolderBookmarkEntry? {
        guard filteredEntries.indices.contains(selectedIndex) else { return nil }
        return filteredEntries[selectedIndex]
    }

    private var selectedEntryIsFavorite: Bool {
        selectedEntry?.isFavorite == true
    }

    private func moveSelection(_ delta: Int) {
        guard !filteredEntries.isEmpty else {
            logDialogEvent("selection.move.ignored.empty", metadata: ["delta": "\(delta)"])
            return
        }
        let previousIndex = selectedIndex
        selectedIndex = min(max(selectedIndex + delta, 0), filteredEntries.count - 1)
        logDialogEvent("selection.moved", metadata: [
            "delta": "\(delta)",
            "previousIndex": "\(previousIndex)",
            "selectedIndex": "\(selectedIndex)",
            "filteredCount": "\(filteredEntries.count)",
            "selectedPath": selectedEntry?.url.path ?? ""
        ])
    }

    private func beginListSelection() {
        isListSelectionActive = true
        isSearchFocused = false
        logDialogEvent("list-selection.begin", metadata: [
            "filteredCount": "\(filteredEntries.count)",
            "selectedIndex": "\(selectedIndex)",
            "selectedPath": selectedEntry?.url.path ?? ""
        ])
        guard !filteredEntries.isEmpty else { return }

        DispatchQueue.main.async {
            NSApp.keyWindow?.makeFirstResponder(nil)
            logDialogEvent("list-selection.first-responder-cleared", metadata: [
                "keyWindow": "\(NSApp.keyWindow != nil)"
            ])
        }
    }

    private func focusSearch() {
        isListSelectionActive = false
        isSearchFocused = true
        logDialogEvent("search.focus.requested", metadata: [
            "query": query,
            "filteredCount": "\(filteredEntries.count)",
            "selectedIndex": "\(selectedIndex)"
        ])
    }

    private func confirmSelection() {
        guard let selectedEntry else {
            logDialogEvent("selection.confirm.ignored.none")
            return
        }
        logDialogEvent("selection.confirmed", metadata: [
            "selectedIndex": "\(selectedIndex)",
            "path": selectedEntry.url.path
        ])
        model.navigateToBookmarkedFolder(selectedEntry.url)
        dismiss()
    }

    private func addCurrentFolder() {
        let currentURL = model.pane(for: model.activePaneSide).selectedURL
        model.addActiveFolderToFavorites()
        reloadEntries(selecting: currentURL)
    }

    private func removeSelectedFavorite() {
        guard let selectedEntry, selectedEntry.isFavorite else { return }
        model.removeFolderFavorite(selectedEntry.url)
        reloadEntries(selecting: selectedEntry.url)
    }

    private func reloadEntries(selecting url: URL? = nil) {
        entries = model.folderBookmarkEntries()
        if let url,
           let index = filteredEntries.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            selectedIndex = index
        }
        clampSelection()
    }

    private func clampSelection() {
        if filteredEntries.isEmpty {
            selectedIndex = 0
        } else {
            selectedIndex = min(selectedIndex, filteredEntries.count - 1)
        }
    }

    private func logDialogEvent(_ message: String, metadata: [String: String] = [:]) {
        model.logFolderBookmarkDialogEvent(message, metadata: metadata)
    }
}

private struct FolderBookmarkDialogKeyHandler: NSViewRepresentable {
    let isListSelectionActive: Bool
    let moveSelection: (Int) -> Void
    let beginListSelection: () -> Void
    let confirmSelection: () -> Void
    let cancel: () -> Void
    let addCurrentFolder: () -> Void
    let removeSelectedFavorite: () -> Void
    let focusSearch: () -> Void
    let logEvent: (String, [String: String]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            isListSelectionActive: isListSelectionActive,
            moveSelection: moveSelection,
            beginListSelection: beginListSelection,
            confirmSelection: confirmSelection,
            cancel: cancel,
            addCurrentFolder: addCurrentFolder,
            removeSelectedFavorite: removeSelectedFavorite,
            focusSearch: focusSearch,
            logEvent: logEvent
        )
    }

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView(frame: .zero)
        view.coordinator = context.coordinator
        context.coordinator.install()
        logEvent("key-handler.make-view", [:])
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        context.coordinator.isListSelectionActive = isListSelectionActive
        context.coordinator.moveSelection = moveSelection
        context.coordinator.beginListSelection = beginListSelection
        context.coordinator.confirmSelection = confirmSelection
        context.coordinator.cancel = cancel
        context.coordinator.addCurrentFolder = addCurrentFolder
        context.coordinator.removeSelectedFavorite = removeSelectedFavorite
        context.coordinator.focusSearch = focusSearch
        context.coordinator.logEvent = logEvent
    }

    static func dismantleNSView(_ nsView: KeyCaptureView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class KeyCaptureView: NSView {
        weak var coordinator: Coordinator?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            coordinator?.install()
            coordinator?.logEvent("key-handler.moved-to-window", [
                "hasWindow": "\(window != nil)"
            ])
        }
    }

    final class Coordinator {
        var isListSelectionActive: Bool
        var moveSelection: (Int) -> Void
        var beginListSelection: () -> Void
        var confirmSelection: () -> Void
        var cancel: () -> Void
        var addCurrentFolder: () -> Void
        var removeSelectedFavorite: () -> Void
        var focusSearch: () -> Void
        var logEvent: (String, [String: String]) -> Void
        private var monitor: Any?

        init(
            isListSelectionActive: Bool,
            moveSelection: @escaping (Int) -> Void,
            beginListSelection: @escaping () -> Void,
            confirmSelection: @escaping () -> Void,
            cancel: @escaping () -> Void,
            addCurrentFolder: @escaping () -> Void,
            removeSelectedFavorite: @escaping () -> Void,
            focusSearch: @escaping () -> Void,
            logEvent: @escaping (String, [String: String]) -> Void
        ) {
            self.isListSelectionActive = isListSelectionActive
            self.moveSelection = moveSelection
            self.beginListSelection = beginListSelection
            self.confirmSelection = confirmSelection
            self.cancel = cancel
            self.addCurrentFolder = addCurrentFolder
            self.removeSelectedFavorite = removeSelectedFavorite
            self.focusSearch = focusSearch
            self.logEvent = logEvent
        }

        func install() {
            guard monitor == nil else {
                logEvent("key-handler.install.skipped", ["reason": "already-installed"])
                return
            }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
            logEvent("key-handler.installed", [:])
        }

        func remove() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
                logEvent("key-handler.removed", [:])
            }
        }

        deinit {
            remove()
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let inputFlags = flags.subtracting([.function, .numericPad])
            if Self.shouldLog(event) {
                logEvent("key-handler.event", [
                    "keyCode": "\(event.keyCode)",
                    "characters": event.charactersIgnoringModifiers ?? "",
                    "flags": "\(flags.rawValue)",
                    "inputFlags": "\(inputFlags.rawValue)",
                    "isListSelectionActive": "\(isListSelectionActive)"
                ])
            }

            if inputFlags.isEmpty {
                switch event.keyCode {
                case 36, 76:
                    if isListSelectionActive {
                        logEvent("key-handler.return.confirm", [:])
                        confirmSelection()
                    } else {
                        isListSelectionActive = true
                        logEvent("key-handler.return.begin-list", [:])
                        beginListSelection()
                    }
                    return nil
                case 126:
                    guard isListSelectionActive else {
                        logEvent("key-handler.up.ignored", ["reason": "list-selection-inactive"])
                        return event
                    }
                    logEvent("key-handler.up.handled", [:])
                    moveSelection(-1)
                    return nil
                case 125:
                    guard isListSelectionActive else {
                        logEvent("key-handler.down.ignored", ["reason": "list-selection-inactive"])
                        return event
                    }
                    logEvent("key-handler.down.handled", [:])
                    moveSelection(1)
                    return nil
                case 53:
                    logEvent("key-handler.escape.cancel", [:])
                    cancel()
                    return nil
                default:
                    return event
                }
            }

            guard flags == .control else { return event }

            switch event.charactersIgnoringModifiers?.lowercased() {
            case "e":
                guard isListSelectionActive else { return event }
                logEvent("key-handler.control-e.focus-search", [:])
                focusSearch()
                return nil
            case "m":
                logEvent("key-handler.control-m.handled", [:])
                addCurrentFolder()
                return nil
            case "r":
                logEvent("key-handler.control-r.handled", [:])
                removeSelectedFavorite()
                return nil
            default:
                return event
            }
        }

        private static func shouldLog(_ event: NSEvent) -> Bool {
            switch event.keyCode {
            case 36, 53, 76, 125, 126:
                return true
            default:
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                return flags == .control
            }
        }
    }
}

private struct FolderBookmarkRow: View {
    let entry: FolderBookmarkEntry
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: entry.isFavorite ? "star.fill" : "clock")
                .foregroundStyle(entry.isFavorite ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .lineLimit(1)
                Text(entry.url.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
    }

    private var displayName: String {
        entry.url.lastPathComponent.isEmpty ? entry.url.path : entry.url.lastPathComponent
    }
}

private struct AppToolbar: View {
    @ObservedObject var model: DualFinderViewModel
    @AppStorage("appearanceMode") private var appearanceMode = AppearanceMode.system.rawValue
    @AppStorage("accentName") private var accentName = AccentChoice.blue.rawValue

    var body: some View {
        HStack(spacing: 8) {
            IconButton(systemName: "arrow.clockwise", help: "Refresh both panes") {
                model.refreshAll()
            }
            IconButton(systemName: "doc.on.doc", help: "Copy left selection to right") {
                model.copySelection(from: .left)
            }
            IconButton(systemName: "doc.on.doc.fill", help: "Copy right selection to left") {
                model.copySelection(from: .right)
            }
            IconButton(systemName: "arrow.right.arrow.left", help: "Move left selection to right") {
                model.moveSelection(from: .left)
            }
            IconButton(systemName: "rectangle.split.2x1", help: "Compare folders") {
                model.requestDirectoryComparison()
            }
            IconButton(systemName: "magnifyingglass", help: "Recursive search") {
                model.requestGlobalSearchDialog()
            }
            Toggle(isOn: $model.showHiddenFiles) {
                Image(systemName: model.showHiddenFiles ? "eye" : "eye.slash")
            }
            .toggleStyle(.button)
            .help("Show hidden files")

            Spacer()

            Picker("", selection: $appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 190)
            .help("Appearance")

            Picker("", selection: $accentName) {
                ForEach(AccentChoice.allCases) { accent in
                    Text(accent.label).tag(accent.rawValue)
                }
            }
            .frame(width: 120)
            .help("Accent color")

            IconButton(systemName: "doc.text.magnifyingglass", help: "Open log folder") {
                model.openLogFolder()
            }
            IconButton(systemName: "lock.shield", help: "Open Full Disk Access settings") {
                model.openFullDiskAccessSettings()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}

private struct StatusBar: View {
    let message: String

    var body: some View {
        HStack {
            Text(message.isEmpty ? "Ready" : message)
                .lineLimit(1)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
    }
}
