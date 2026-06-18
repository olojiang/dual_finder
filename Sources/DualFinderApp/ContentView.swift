import AppKit
import SwiftUI
import DualFinderCore

struct ContentView: View {
    @ObservedObject var model: DualFinderViewModel
    @StateObject private var leftTerminalModel = EmbeddedTerminalPaneModel()
    @StateObject private var rightTerminalModel = EmbeddedTerminalPaneModel()
    @State private var isOperationHistoryPresented = false

    var body: some View {
        VStack(spacing: 0) {
            AppToolbar(model: model, isOperationHistoryPresented: $isOperationHistoryPresented)
            Divider()
            mainContent
            Divider()
            OperationQueueBar(model: model)
            StatusBar(message: model.statusMessage)
        }
        .background(.background)
        .background(AppShortcutHandler(isSuspended: isGlobalShortcutSuspended) {
            model.addTab(on: model.activePaneSide)
        } newRightTab: {
            model.addTab(on: .right)
        } showShortcutHelp: {
            model.requestShortcutHelp()
        } goToFolder: {
            model.requestPathEditing(on: model.activePaneSide)
        } showFileSearch: {
            model.requestFileSearch(on: model.activePaneSide)
        } showFolderBookmarks: {
            model.requestFolderBookmarkDialog(on: model.activePaneSide)
        } showBatchRename: {
            model.requestBatchRenameDialog(on: model.activePaneSide)
        } closeActiveTab: {
            if closeFocusedTerminalTab() {
                return true
            }
            return model.closeSelectedTab(on: model.activePaneSide)
        } handleTerminalShortcut: { event in
            handleTerminalShortcut(event)
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
        } copyLeftSelectionToRight: {
            model.copySelection(from: .left)
        } copyRightSelectionToLeft: {
            model.copySelection(from: .right)
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
                .interactiveDismissDisabled(true)
        }
        .sheet(item: $model.directoryComparisonDialogRequest) { _ in
            DirectoryComparisonDialog(model: model)
        }
        .sheet(item: $model.globalSearchDialogRequest) { _ in
            GlobalSearchDialog(model: model)
        }
        .sheet(item: $model.shortcutHelpRequest) { _ in
            ShortcutHelpDialog()
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
        .alert("Enable Global \(ShowWindowHotkeyStore().binding().displayLabel)", isPresented: showWindowHotkeyAlertBinding) {
            Button("Open Login Items") {
                model.openShowWindowHotkeySettings()
            }
            Button("Retry Registration") {
                model.retryShowWindowHotkeyHelperRegistration()
            }
            Button("Later", role: .cancel) {
                model.dismissShowWindowHotkeyPrompt()
            }
        } message: {
            Text(model.showWindowHotkeyPrompt?.message ?? "")
        }
    }

    private func closeFocusedTerminalTab() -> Bool {
        guard let focusedView = NSApp.keyWindow?.firstResponder as? NSView else { return false }
        return leftTerminalModel.closeTab(containing: focusedView)
            || rightTerminalModel.closeTab(containing: focusedView)
    }

    private func handleTerminalShortcut(_ event: NSEvent) -> Bool {
        guard let focusedTerminal = focusedTerminal(in: event.window ?? NSApp.keyWindow) else {
            return false
        }

        if let direction = EmbeddedTerminalFocusDirection.commandArrowDirection(for: event) {
            focusedTerminal.model.focusAdjacentTab(from: focusedTerminal.tabID, direction: direction)
            return true
        }

        if let index = terminalOptionNumberIndex(for: event) {
            focusedTerminal.model.selectTab(atZeroBasedIndex: index, focus: true)
            return true
        }

        return false
    }

    private func focusedTerminal(in window: NSWindow?) -> (model: EmbeddedTerminalPaneModel, tabID: UUID)? {
        guard let focusedView = window?.firstResponder as? NSView else { return nil }
        if let tabID = leftTerminalModel.tabID(containing: focusedView) {
            return (leftTerminalModel, tabID)
        }
        if let tabID = rightTerminalModel.tabID(containing: focusedView) {
            return (rightTerminalModel, tabID)
        }
        return nil
    }

    private func terminalOptionNumberIndex(for event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == [.option],
              let character = event.charactersIgnoringModifiers?.first,
              let number = character.wholeNumberValue,
              (1...9).contains(number) else {
            return nil
        }
        return number - 1
    }

    @ViewBuilder
    private var mainContent: some View {
        if let maximizedSide = maximizedTerminalSide {
            maximizedTerminalPanel(for: maximizedSide)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            DualPaneSplitLayout(
                sidebarWidth: model.uiLayoutPreferences.sidebarWidth,
                leftPaneFraction: model.uiLayoutPreferences.leftPaneFraction,
                onResizeLeftPaneFraction: model.setLeftPaneFraction,
                onResizeLeftPaneEnded: model.commitUILayoutPreferences
            ) {
                CommonLocationsSidebar(model: model)
            } leftPane: {
                FilePaneView(
                    side: .left,
                    model: model,
                    terminalModel: leftTerminalModel,
                    onToggleTerminalMaximized: toggleTerminalMaximized
                )
            } rightPane: {
                FilePaneView(
                    side: .right,
                    model: model,
                    terminalModel: rightTerminalModel,
                    onToggleTerminalMaximized: toggleTerminalMaximized
                )
            } trailing: {
                if isOperationHistoryPresented {
                    Divider()
                    OperationHistoryPanel(model: model)
                        .frame(width: 300)
                }
            }
        }
    }

    private var maximizedTerminalSide: PaneSide? {
        if leftTerminalModel.isMaximized {
            return .left
        }
        if rightTerminalModel.isMaximized {
            return .right
        }
        return nil
    }

    private func maximizedTerminalPanel(for side: PaneSide) -> some View {
        EmbeddedTerminalPanel(
            side: side,
            paneModel: terminalModel(for: side),
            currentDirectory: terminalDirectory(for: side),
            openExternal: { directory in
                model.openInTerminal(Set([directory]), on: side)
            },
            toggleMaximized: {
                toggleTerminalMaximized(side)
            }
        )
    }

    private func toggleTerminalMaximized(_ side: PaneSide) {
        let terminalModel = terminalModel(for: side)
        let otherSide: PaneSide = side == .left ? .right : .left
        if !terminalModel.isMaximized {
            self.terminalModel(for: otherSide).isMaximized = false
        }
        terminalModel.toggleMaximized(currentDirectory: terminalDirectory(for: side))
    }

    private func terminalModel(for side: PaneSide) -> EmbeddedTerminalPaneModel {
        side == .left ? leftTerminalModel : rightTerminalModel
    }

    private func terminalDirectory(for side: PaneSide) -> URL {
        let url = model.pane(for: side).selectedURL
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url.standardizedFileURL
        }
        return url.deletingLastPathComponent().standardizedFileURL
    }

    private var showWindowHotkeyAlertBinding: Binding<Bool> {
        Binding(
            get: { model.showWindowHotkeyPrompt != nil },
            set: { isPresented in
                if !isPresented {
                    model.dismissShowWindowHotkeyPrompt()
                }
            }
        )
    }

    private var isGlobalShortcutSuspended: Bool {
        model.folderBookmarkDialogRequest != nil
            || model.batchRenameDialogRequest != nil
            || model.fileConflictDialogRequest != nil
            || model.directoryComparisonDialogRequest != nil
            || model.globalSearchDialogRequest != nil
            || model.shortcutHelpRequest != nil
    }
}

private struct CommonLocationsSidebar: View {
    @ObservedObject var model: DualFinderViewModel

    private var isCollapsed: Bool {
        model.uiLayoutPreferences.isSidebarCollapsed
    }

    private var favorites: [FolderBookmarkEntry] {
        _ = model.folderBookmarkRevision
        return model.folderBookmarkEntries().filter(\.isFavorite)
    }

    private var recents: [FolderBookmarkEntry] {
        _ = model.folderBookmarkRevision
        return Array(model.folderBookmarkEntries().filter { !$0.isFavorite }.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !isCollapsed {
                    Text("Locations")
                        .font(.headline)
                }
                Spacer()
                if !isCollapsed {
                    IconButton(systemName: "star.badge.plus", help: "Add active folder to favorites") {
                        model.addActiveFolderToFavorites()
                    }
                }
                IconButton(
                    systemName: isCollapsed ? "sidebar.right" : "sidebar.left",
                    help: isCollapsed ? "Expand locations sidebar" : "Collapse locations sidebar"
                ) {
                    model.toggleSidebarCollapsed()
                }
            }
            .padding(.horizontal, isCollapsed ? 6 : 12)
            .padding(.vertical, 10)

            ScrollView {
                VStack(alignment: isCollapsed ? .center : .leading, spacing: 14) {
                    sidebarSection("Pinned", entries: pinnedEntries)
                    if !favorites.isEmpty {
                        sidebarSection("Favorites", entries: favorites)
                    }
                    if !recents.isEmpty {
                        sidebarSection("Recent", entries: recents)
                    }
                }
                .padding(.horizontal, isCollapsed ? 4 : 8)
                .padding(.bottom, 12)
            }
        }
        .background(.bar.opacity(0.45))
    }

    private var pinnedEntries: [FolderBookmarkEntry] {
        let fileManager = FileManager.default
        return [
            fileManager.homeDirectoryForCurrentUser,
            fileManager.urls(for: .desktopDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .documentDirectory, in: .userDomainMask).first,
            fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first,
            URL(fileURLWithPath: "/Applications", isDirectory: true)
        ]
        .compactMap { $0 }
        .map { FolderBookmarkEntry(url: $0, isFavorite: false) }
    }

    private func sidebarSection(_ title: String, entries: [FolderBookmarkEntry]) -> some View {
        VStack(alignment: isCollapsed ? .center : .leading, spacing: 4) {
            if !isCollapsed {
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
            }
            ForEach(entries) { entry in
                CommonLocationRow(
                    entry: entry,
                    isActive: isActive(entry.url),
                    isCollapsed: isCollapsed,
                    open: {
                        model.navigateToBookmarkedFolder(entry.url)
                    },
                    removeFavorite: {
                        model.removeFolderFavorite(entry.url)
                    }
                )
            }
        }
    }

    private func isActive(_ url: URL) -> Bool {
        model.pane(for: model.activePaneSide).selectedURL.standardizedFileURL == url.standardizedFileURL
    }
}

private struct CommonLocationRow: View {
    let entry: FolderBookmarkEntry
    let isActive: Bool
    let isCollapsed: Bool
    let open: () -> Void
    let removeFavorite: () -> Void
    @State private var isRemoveConfirmationPresented = false

    var body: some View {
        Group {
            if isCollapsed {
                collapsedRow
            } else {
                expandedRow
            }
        }
        .help(entry.url.path)
        .contextMenu {
            if entry.isFavorite {
                Button("Remove Favorite") {
                    isRemoveConfirmationPresented = true
                }
            }
        }
        .confirmationDialog(
            "Remove from Favorites?",
            isPresented: $isRemoveConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive, action: removeFavorite)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \"\(displayName)\" from your favorites?")
        }
    }

    private var expandedRow: some View {
        HStack(spacing: 8) {
            favoriteStarButton
            rowLabel
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture(perform: open)
    }

    private var collapsedRow: some View {
        Button(action: open) {
            rowIcon
                .frame(width: 28, height: 28)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var rowIcon: some View {
        if entry.isFavorite {
            Image(systemName: "star.fill")
                .foregroundStyle(Color.accentColor)
        } else {
            Image(systemName: iconName)
                .foregroundStyle(Color.secondary)
        }
    }

    @ViewBuilder
    private var favoriteStarButton: some View {
        if entry.isFavorite {
            Button {
                isRemoveConfirmationPresented = true
            } label: {
                Image(systemName: "star.fill")
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)
            .help("Remove from favorites")
        } else {
            Image(systemName: iconName)
                .foregroundStyle(Color.secondary)
                .frame(width: 18)
        }
    }

    private var rowLabel: some View {
        HStack(spacing: 8) {
            Text(displayName)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
    }

    private var iconName: String {
        if entry.isFavorite { return "star.fill" }
        switch entry.url.standardizedFileURL.path {
        case FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path:
            return "house"
        case "/Applications":
            return "app.gift"
        default:
            return "folder"
        }
    }

    private var displayName: String {
        entry.url.lastPathComponent.isEmpty ? entry.url.path : entry.url.lastPathComponent
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

private struct OperationHistoryPanel: View {
    @ObservedObject var model: DualFinderViewModel

    private var finishedOperations: [QueuedFileOperation] {
        Array(model.fileOperationQueue
            .filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
            .reversed())
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Operation History")
                    .font(.headline)
                Spacer()
                IconButton(systemName: "trash", help: "Clear finished operations") {
                    model.clearFinishedFileOperations()
                }
                .disabled(finishedOperations.isEmpty)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            if finishedOperations.isEmpty {
                ContentUnavailableView("No finished operations", systemImage: "clock.arrow.circlepath")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(finishedOperations) { operation in
                    OperationHistoryRow(model: model, operation: operation)
                }
                .listStyle(.plain)
            }
        }
        .background(.bar)
    }
}

private struct OperationHistoryRow: View {
    @ObservedObject var model: DualFinderViewModel
    let operation: QueuedFileOperation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(operation.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(destinationText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
                Text(operation.status.rawValue.capitalized)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(statusColor)
            }

            Text(operation.message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            if operation.status == .failed {
                Text(model.recoverySuggestion(for: operation))
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }

            HStack {
                Text(timestampText)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Retry") {
                    model.retryFileOperation(operation.id)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canRetryFileOperation(operation.id))
            }
        }
        .padding(.vertical, 6)
        .help(helpText)
    }

    private var iconName: String {
        switch operation.status {
        case .completed: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        case .cancelled: "xmark.circle"
        case .queued: "clock"
        case .running: "arrow.triangle.2.circlepath"
        }
    }

    private var statusColor: Color {
        switch operation.status {
        case .completed: .green
        case .failed: .orange
        case .cancelled: .secondary
        case .queued, .running: .accentColor
        }
    }

    private var destinationText: String {
        if let destination = operation.destination {
            return destination.path
        }
        return operation.sources.count == 1 ? operation.sources[0].path : "\(operation.sources.count) source items"
    }

    private var timestampText: String {
        (operation.finishedAt ?? operation.createdAt).formatted(date: .omitted, time: .shortened)
    }

    private var helpText: String {
        let sources = operation.sources.map(\.path).joined(separator: "\n")
        if let destination = operation.destination {
            return "\(sources)\n→ \(destination.path)"
        }
        return sources
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
            HStack(alignment: .top, spacing: 16) {
                ConflictFileInfoColumn(url: request.source, role: "Source")
                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 1)
                ConflictFileInfoColumn(url: request.destination, role: "Destination")
            }
            Text(request.destination.deletingLastPathComponent().path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
            ConflictPreviewList(request: request)
            Toggle("Apply to all conflicts", isOn: $applyToAll)
            HStack {
                Button("Skip") {
                    model.resolveFileConflict(.skip, applyToAll: applyToAll)
                }
                Spacer()
                Button("Keep Both") {
                    model.resolveFileConflict(.keepBoth, applyToAll: applyToAll)
                }
                Button("Larger Wins") {
                    model.resolveFileConflict(.largerWins, applyToAll: applyToAll)
                }
                Button("Overwrite", role: .destructive) {
                    model.resolveFileConflict(.overwrite, applyToAll: applyToAll)
                }
            }
        }
        .padding(18)
        .frame(width: 620)
    }
}

private struct ConflictPreviewList: View {
    let request: FileConflictDialogRequest

    private var conflicts: [FileConflictPreview] {
        if request.conflicts.isEmpty {
            return [
                FileConflictPreview(
                    source: request.source,
                    destination: request.destination,
                    sourceSize: ConflictFileInfo.fetch(for: request.source).size,
                    destinationSize: ConflictFileInfo.fetch(for: request.destination).size,
                    largerWinsResolution: FileOperationService.largerWinsResolution(
                        for: FileOperationConflict(source: request.source, destination: request.destination)
                    )
                )
            ]
        }
        return request.conflicts
    }

    private var overwriteCount: Int {
        conflicts.filter { $0.largerWinsResolution == .overwrite }.count
    }

    private var skipCount: Int {
        conflicts.count - overwriteCount
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(conflicts.count) conflict(s)")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text("Larger Wins: \(overwriteCount) overwrite, \(skipCount) skip")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(conflicts) { conflict in
                        ConflictPreviewRow(conflict: conflict, isCurrent: isCurrent(conflict))
                        if conflict.id != conflicts.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .frame(maxHeight: 190)
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.2))
            }
        }
    }

    private func isCurrent(_ conflict: FileConflictPreview) -> Bool {
        conflict.source == request.source && conflict.destination == request.destination
    }
}

private struct ConflictPreviewRow: View {
    let conflict: FileConflictPreview
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isCurrent ? "arrowtriangle.right.fill" : "doc")
                .font(.caption)
                .foregroundStyle(isCurrent ? Color.accentColor : Color.secondary)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(conflict.source.lastPathComponent)
                    .font(.caption)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Source \(sizeText(conflict.sourceSize)) | Destination \(sizeText(conflict.destinationSize))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(actionText)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(actionColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(actionColor.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var actionText: String {
        conflict.largerWinsResolution == .overwrite ? "Overwrite" : "Skip"
    }

    private var actionColor: Color {
        conflict.largerWinsResolution == .overwrite ? .orange : .secondary
    }

    private func sizeText(_ size: Int64?) -> String {
        guard let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }
}

private struct ConflictFileInfoColumn: View {
    let url: URL
    let role: String
    @State private var fileInfo: ConflictFileInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(role.uppercased())
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            Text(url.lastPathComponent)
                .font(.body)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.middle)
            Label(fileInfo?.sizeText ?? "—", systemImage: "scalemass")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Label(fileInfo?.modifiedText ?? "—", systemImage: "clock")
                .labelStyle(.titleAndIcon)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: url) {
            fileInfo = ConflictFileInfo.fetch(for: url)
        }
    }
}

private struct ConflictFileInfo {
    let size: Int64?
    let modifiedAt: Date?

    static func fetch(for url: URL) -> ConflictFileInfo {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        return ConflictFileInfo(
            size: values?.isRegularFile == true ? values?.fileSize.map(Int64.init) : nil,
            modifiedAt: values?.contentModificationDate
        )
    }

    var sizeText: String {
        guard let size else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    var modifiedText: String {
        guard let modifiedAt else { return "—" }
        return modifiedAt.formatted(date: .abbreviated, time: .shortened)
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

private struct ShortcutHelpDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var isSearchFocused: Bool

    private var filteredGroups: [ShortcutHelpGroup] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
        guard !trimmedQuery.isEmpty else { return ShortcutHelpCatalog.groups }

        return ShortcutHelpCatalog.groups.compactMap { group in
            let entries = group.entries.filter { entry in
                entry.searchText.localizedLowercase.contains(trimmedQuery)
            }
            return entries.isEmpty ? nil : ShortcutHelpGroup(title: group.title, entries: entries)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "keyboard")
                    .foregroundStyle(.secondary)
                Text("Keyboard Shortcuts")
                    .font(.headline)
                Spacer()
                IconButton(systemName: "xmark", help: "Close") {
                    dismiss()
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search shortcuts", text: $query)
                    .textFieldStyle(.plain)
                    .focused($isSearchFocused)
                if !query.isEmpty {
                    Button {
                        query = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help("Clear search")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 18)
            .padding(.bottom, 10)

            if filteredGroups.isEmpty {
                ContentUnavailableView("No shortcuts found", systemImage: "keyboard.badge.ellipsis")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredGroups) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title)
                                            .lineLimit(1)
                                        if let note = entry.note {
                                            Text(note)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Text(entry.shortcut)
                                        .font(.system(.body, design: .monospaced))
                                        .fontWeight(.semibold)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(width: 640, height: 620)
        .onAppear {
            isSearchFocused = true
        }
    }
}

private struct ShortcutHelpGroup: Identifiable {
    let title: String
    let entries: [ShortcutHelpEntry]

    var id: String { title }
}

private struct ShortcutHelpEntry: Identifiable {
    let title: String
    let shortcut: String
    let note: String?

    var id: String { "\(title)-\(shortcut)" }
    var searchText: String { "\(title) \(shortcut) \(note ?? "")" }
}

private enum ShortcutHelpCatalog {
    static var groups: [ShortcutHelpGroup] {
        [
            ShortcutHelpGroup(title: "Tabs", entries: [
                entry(.newActiveTab, note: "Uses the focused pane"),
                entry(.newRightTab),
                entry(.closeActiveTab),
                ShortcutHelpEntry(
                    title: "Select Tab 1...9",
                    shortcut: "\(AppShortcutMatrix.binding(for: .selectTab1).displayText) ... \(AppShortcutMatrix.binding(for: .selectTab9).displayText)",
                    note: "Current active pane"
                )
            ]),
            ShortcutHelpGroup(title: "Navigation", entries: [
                entry(.focusLeftPane),
                entry(.focusRightPane),
                entry(.navigateBack),
                entry(.navigateForward),
                ShortcutHelpEntry(title: "Go to Parent Folder", shortcut: "⌘↑", note: nil),
                ShortcutHelpEntry(title: "Open Selection or Enter Folder", shortcut: "⌘↓", note: nil),
                entry(.goToFolder),
                entry(.folderBookmarks)
            ]),
            ShortcutHelpGroup(title: "Search and Tools", entries: [
                entry(.fileSearch),
                ShortcutHelpEntry(title: "Focus Filter Input", shortcut: "⌃E", note: "When folder filter is open"),
                ShortcutHelpEntry(title: "Recursive Search", shortcut: "Menu", note: nil),
                ShortcutHelpEntry(title: "Compare Directories", shortcut: "Menu", note: nil),
                entry(.showShortcutHelp)
            ]),
            ShortcutHelpGroup(title: "Selection and Files", entries: [
                ShortcutHelpEntry(title: "Select All", shortcut: "⌘A", note: nil),
                ShortcutHelpEntry(title: "Rename", shortcut: "Return", note: "Single selected item"),
                entry(.batchRename),
                ShortcutHelpEntry(title: "Open Selection", shortcut: "⌘O", note: nil),
                ShortcutHelpEntry(title: "Quick Look", shortcut: "Space", note: nil),
                ShortcutHelpEntry(title: "Calculate Folder Size", shortcut: "⌃Space", note: nil)
            ]),
            ShortcutHelpGroup(title: "Clipboard and Transfer", entries: [
                ShortcutHelpEntry(title: "Copy Files", shortcut: "⌘C", note: nil),
                ShortcutHelpEntry(title: "Copy Absolute Path", shortcut: "⌘⌥C", note: nil),
                ShortcutHelpEntry(title: "Paste Files", shortcut: "⌘V", note: nil),
                ShortcutHelpEntry(title: "Paste and Move", shortcut: "⌘⌥V", note: nil),
                ShortcutHelpEntry(title: "Move Selection to Trash", shortcut: "⌘Delete", note: nil),
                ShortcutHelpEntry(title: "Empty Trash", shortcut: "⌘⇧Delete", note: nil),
                ShortcutHelpEntry(title: "Open in Ghostty or Terminal", shortcut: "⌘⌥T", note: nil),
                entry(.copyLeftSelectionToRight),
                entry(.copyRightSelectionToLeft),
                entry(.moveLeftSelectionToRight),
                entry(.moveRightSelectionToLeft)
            ])
        ]
    }

    private static func entry(_ action: AppShortcutAction, note: String? = nil) -> ShortcutHelpEntry {
        ShortcutHelpEntry(
            title: action.title,
            shortcut: AppShortcutMatrix.binding(for: action).displayText,
            note: note
        )
    }
}

private struct AppShortcutHandler: NSViewRepresentable {
    let isSuspended: Bool
    let newActiveTab: () -> Void
    let newRightTab: () -> Void
    let showShortcutHelp: () -> Void
    let goToFolder: () -> Void
    let showFileSearch: () -> Void
    let showFolderBookmarks: () -> Void
    let showBatchRename: () -> Void
    let closeActiveTab: () -> Bool
    let handleTerminalShortcut: (NSEvent) -> Bool
    let focusPane: (PaneSide, String) -> Void
    let selectTab: (Int, String) -> Void
    let logShortcutEvent: (String, [String: String]) -> Void
    let navigateBack: () -> Void
    let navigateForward: () -> Void
    let copyLeftSelectionToRight: () -> Void
    let copyRightSelectionToLeft: () -> Void
    let moveLeftSelectionToRight: () -> Void
    let moveRightSelectionToLeft: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            newActiveTab: newActiveTab,
            newRightTab: newRightTab,
            showShortcutHelp: showShortcutHelp,
            goToFolder: goToFolder,
            showFileSearch: showFileSearch,
            showFolderBookmarks: showFolderBookmarks,
            showBatchRename: showBatchRename,
            closeActiveTab: closeActiveTab,
            handleTerminalShortcut: handleTerminalShortcut,
            focusPane: focusPane,
            selectTab: selectTab,
            logShortcutEvent: logShortcutEvent,
            navigateBack: navigateBack,
            navigateForward: navigateForward,
            copyLeftSelectionToRight: copyLeftSelectionToRight,
            copyRightSelectionToLeft: copyRightSelectionToLeft,
            moveLeftSelectionToRight: moveLeftSelectionToRight,
            moveRightSelectionToLeft: moveRightSelectionToLeft,
            isSuspended: isSuspended
        )
    }

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.newActiveTab = newActiveTab
        context.coordinator.newRightTab = newRightTab
        context.coordinator.showShortcutHelp = showShortcutHelp
        context.coordinator.goToFolder = goToFolder
        context.coordinator.showFileSearch = showFileSearch
        context.coordinator.showFolderBookmarks = showFolderBookmarks
        context.coordinator.showBatchRename = showBatchRename
        context.coordinator.closeActiveTab = closeActiveTab
        context.coordinator.handleTerminalShortcut = handleTerminalShortcut
        context.coordinator.focusPane = focusPane
        context.coordinator.selectTab = selectTab
        context.coordinator.logShortcutEvent = logShortcutEvent
        context.coordinator.navigateBack = navigateBack
        context.coordinator.navigateForward = navigateForward
        context.coordinator.copyLeftSelectionToRight = copyLeftSelectionToRight
        context.coordinator.copyRightSelectionToLeft = copyRightSelectionToLeft
        context.coordinator.moveLeftSelectionToRight = moveLeftSelectionToRight
        context.coordinator.moveRightSelectionToLeft = moveRightSelectionToLeft
        context.coordinator.isSuspended = isSuspended
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.remove()
    }

    final class Coordinator {
        var newActiveTab: () -> Void
        var newRightTab: () -> Void
        var showShortcutHelp: () -> Void
        var goToFolder: () -> Void
        var showFileSearch: () -> Void
        var showFolderBookmarks: () -> Void
        var showBatchRename: () -> Void
        var closeActiveTab: () -> Bool
        var handleTerminalShortcut: (NSEvent) -> Bool
        var focusPane: (PaneSide, String) -> Void
        var selectTab: (Int, String) -> Void
        var logShortcutEvent: (String, [String: String]) -> Void
        var navigateBack: () -> Void
        var navigateForward: () -> Void
        var copyLeftSelectionToRight: () -> Void
        var copyRightSelectionToLeft: () -> Void
        var moveLeftSelectionToRight: () -> Void
        var moveRightSelectionToLeft: () -> Void
        var isSuspended: Bool
        private var monitor: Any?

        init(
            newActiveTab: @escaping () -> Void,
            newRightTab: @escaping () -> Void,
            showShortcutHelp: @escaping () -> Void,
            goToFolder: @escaping () -> Void,
            showFileSearch: @escaping () -> Void,
            showFolderBookmarks: @escaping () -> Void,
            showBatchRename: @escaping () -> Void,
            closeActiveTab: @escaping () -> Bool,
            handleTerminalShortcut: @escaping (NSEvent) -> Bool,
            focusPane: @escaping (PaneSide, String) -> Void,
            selectTab: @escaping (Int, String) -> Void,
            logShortcutEvent: @escaping (String, [String: String]) -> Void,
            navigateBack: @escaping () -> Void,
            navigateForward: @escaping () -> Void,
            copyLeftSelectionToRight: @escaping () -> Void,
            copyRightSelectionToLeft: @escaping () -> Void,
            moveLeftSelectionToRight: @escaping () -> Void,
            moveRightSelectionToLeft: @escaping () -> Void,
            isSuspended: Bool
        ) {
            self.newActiveTab = newActiveTab
            self.newRightTab = newRightTab
            self.showShortcutHelp = showShortcutHelp
            self.goToFolder = goToFolder
            self.showFileSearch = showFileSearch
            self.showFolderBookmarks = showFolderBookmarks
            self.showBatchRename = showBatchRename
            self.closeActiveTab = closeActiveTab
            self.handleTerminalShortcut = handleTerminalShortcut
            self.focusPane = focusPane
            self.selectTab = selectTab
            self.logShortcutEvent = logShortcutEvent
            self.navigateBack = navigateBack
            self.navigateForward = navigateForward
            self.copyLeftSelectionToRight = copyLeftSelectionToRight
            self.copyRightSelectionToLeft = copyRightSelectionToLeft
            self.moveLeftSelectionToRight = moveLeftSelectionToRight
            self.moveRightSelectionToLeft = moveRightSelectionToLeft
            self.isSuspended = isSuspended
        }

        func install() {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard self?.isSuspended != true else { return event }
                if self?.handleTerminalShortcut(event) == true {
                    return nil
                }
                guard let action = AppShortcutMatrix.action(matching: event) else {
                    return event
                }

                switch action {
                case .newActiveTab:
                    self?.newActiveTab()
                    return nil
                case .newRightTab:
                    self?.newRightTab()
                    return nil
                case .goToFolder:
                    self?.goToFolder()
                    return nil
                case .fileSearch:
                    self?.showFileSearch()
                    return nil
                case .folderBookmarks:
                    self?.showFolderBookmarks()
                    return nil
                case .batchRename:
                    self?.showBatchRename()
                    return nil
                case .closeActiveTab:
                    guard self?.closeActiveTab() == true else { return event }
                    return nil
                case .showShortcutHelp:
                    self?.showShortcutHelp()
                    return nil
                case .focusLeftPane:
                    self?.handlePaneFocusShortcut(event, target: .left)
                    return nil
                case .focusRightPane:
                    self?.handlePaneFocusShortcut(event, target: .right)
                    return nil
                case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9:
                    if let tabIndex = action.tabIndex {
                        self?.handleTabSelectionShortcut(event, index: tabIndex)
                    }
                    return nil
                case .navigateBack:
                    self?.navigateBack()
                    return nil
                case .navigateForward:
                    self?.navigateForward()
                    return nil
                case .copyLeftSelectionToRight:
                    self?.copyLeftSelectionToRight()
                    return nil
                case .copyRightSelectionToLeft:
                    self?.copyRightSelectionToLeft()
                    return nil
                case .moveLeftSelectionToRight:
                    self?.moveLeftSelectionToRight()
                    return nil
                case .moveRightSelectionToLeft:
                    self?.moveRightSelectionToLeft()
                    return nil
                }
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
                                        isSelected: index == selectedIndex,
                                        shortcutLabel: shortcutLabel(for: index)
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
                openShortcutIndex: openShortcutIndex,
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
        .onChange(of: model.folderBookmarkRevision) { _, _ in
            reloadEntries(selecting: selectedEntry?.url)
        }
    }

    private var selectedEntry: FolderBookmarkEntry? {
        guard filteredEntries.indices.contains(selectedIndex) else { return nil }
        return filteredEntries[selectedIndex]
    }

    private var selectedEntryIsFavorite: Bool {
        selectedEntry?.isFavorite == true
    }

    private func shortcutLabel(for index: Int) -> String? {
        guard (0..<9).contains(index) else { return nil }
        return "⌘\(index + 1)"
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

    private func openShortcutIndex(_ index: Int) {
        guard filteredEntries.indices.contains(index) else {
            logDialogEvent("shortcut.open.ignored.out-of-range", metadata: [
                "index": "\(index)",
                "filteredCount": "\(filteredEntries.count)"
            ])
            return
        }

        let entry = filteredEntries[index]
        selectedIndex = index
        isListSelectionActive = true
        logDialogEvent("shortcut.open.confirmed", metadata: [
            "shortcut": "cmd+\(index + 1)",
            "selectedIndex": "\(index)",
            "path": entry.url.path
        ])
        model.navigateToBookmarkedFolder(entry.url)
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
    let openShortcutIndex: (Int) -> Void
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
            openShortcutIndex: openShortcutIndex,
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
        context.coordinator.openShortcutIndex = openShortcutIndex
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
        var openShortcutIndex: (Int) -> Void
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
            openShortcutIndex: @escaping (Int) -> Void,
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
            self.openShortcutIndex = openShortcutIndex
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

            if inputFlags == .command,
               let shortcutIndex = Self.commandNumberIndex(for: event) {
                logEvent("key-handler.command-number.open", [
                    "characters": event.charactersIgnoringModifiers ?? "",
                    "index": "\(shortcutIndex)"
                ])
                openShortcutIndex(shortcutIndex)
                return nil
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
                let inputFlags = flags.subtracting([.function, .numericPad])
                return inputFlags == .control || inputFlags == .command
            }
        }

        private static func commandNumberIndex(for event: NSEvent) -> Int? {
            guard let characters = event.charactersIgnoringModifiers,
                  let digit = Int(characters),
                  (1...9).contains(digit)
            else {
                return nil
            }
            return digit - 1
        }
    }
}

private struct FolderBookmarkRow: View {
    let entry: FolderBookmarkEntry
    let isSelected: Bool
    let shortcutLabel: String?

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
            if let shortcutLabel {
                Text(shortcutLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospaced()
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(isSelected ? 0.18 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Shortcut \(shortcutLabel)")
            }
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
    @Binding var isOperationHistoryPresented: Bool
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
            Toggle(isOn: $isOperationHistoryPresented) {
                Image(systemName: "clock.arrow.circlepath")
            }
            .toggleStyle(.button)
            .help("Show operation history and recovery")
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
