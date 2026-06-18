import SwiftUI

/// Menu bar commands grouped to match Dual Finder features and selection state.
struct AppMenuCommands: Commands {
    @ObservedObject var model: DualFinderViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            tabCommands
            Divider()
            createCommands
            Divider()
            navigationCommands
            Divider()
            trashCommands
        }

        CommandGroup(replacing: .undoRedo) { }

        CommandGroup(replacing: .pasteboard) {
            editClipboardCommands
            Divider()
            editSelectionCommands
        }

        CommandMenu("View") {
            viewDisplayCommands
            Divider()
            viewNavigationCommands
            Divider()
            viewToolCommands
        }

        CommandMenu("Pane") {
            paneTransferCommands
            Divider()
            paneIntegrationCommands
            Divider()
            paneArchiveCommands
        }
    }

    // MARK: - File (replaces New)

    @ViewBuilder
    private var tabCommands: some View {
        Button("New Tab in Active Pane") { model.addTab(on: model.activePaneSide) }
            .keyboardShortcut("t", modifiers: [.command])
        Button("New Right Tab") { model.addTab(on: .right) }
            .keyboardShortcut("t", modifiers: [.command, .shift])
        Button("Close Active Tab") { model.closeSelectedTab(on: model.activePaneSide) }
            .keyboardShortcut("w", modifiers: [.command])
    }

    @ViewBuilder
    private var createCommands: some View {
        Button("New Folder") {
            if let created = model.createFolder(in: model.activePaneSide) {
                model.requestInlineRename(for: created, on: model.activePaneSide)
            }
        }
        .disabled(!model.canCreateInActivePane)

        Button("New Empty Text File") {
            if let created = model.createEmptyFile(named: "New File.txt", in: model.activePaneSide) {
                model.requestInlineRename(for: created, on: model.activePaneSide)
            }
        }
        .disabled(!model.canCreateInActivePane)

        Button("New Markdown File") {
            if let created = model.createEmptyFile(named: "New File.md", in: model.activePaneSide) {
                model.requestInlineRename(for: created, on: model.activePaneSide)
            }
        }
        .disabled(!model.canCreateInActivePane)
    }

    @ViewBuilder
    private var navigationCommands: some View {
        Button("Go to Folder…") {
            model.requestPathEditing(on: model.activePaneSide)
        }
        .keyboardShortcut("g", modifiers: [.command, .shift])

        Button("Open Locations…") {
            model.requestFolderBookmarkDialog(on: model.activePaneSide)
        }
        .keyboardShortcut("d", modifiers: [.control])

        Button("Choose Folder…") {
            model.chooseFolder(for: model.activePaneSide)
        }
        .disabled(model.isInlineRenaming)
    }

    @ViewBuilder
    private var trashCommands: some View {
        Button("Move Selection to Trash") {
            model.trashActiveSelection()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(!model.canTrashActiveSelection)

        Button("Empty Trash") {
            model.emptyTrash()
        }
        .keyboardShortcut(.delete, modifiers: [.command, .shift])
        .disabled(!model.canEmptyTrash)
    }

    // MARK: - Edit

    @ViewBuilder
    private var editClipboardCommands: some View {
        Button("Copy") {
            model.copySelectionToFileClipboard(on: model.activePaneSide)
        }
        .keyboardShortcut("c", modifiers: [.command])
        .disabled(!model.canCopyActiveSelection)

        Button("Paste") {
            model.pasteFileClipboard(into: model.activePaneSide, operation: .copy)
        }
        .keyboardShortcut("v", modifiers: [.command])
        .disabled(!model.canPasteToActivePane)

        Button("Paste and Move") {
            model.pasteFileClipboard(into: model.activePaneSide, operation: .move)
        }
        .keyboardShortcut("v", modifiers: [.command, .option])
        .disabled(!model.canPasteToActivePane)

        Button("Copy Absolute Path") {
            let side = model.activePaneSide
            model.copyAbsolutePaths(model.pane(for: side).selectedItemURLs, on: side)
        }
        .keyboardShortcut("c", modifiers: [.command, .option])
        .disabled(!model.canCopyAbsolutePathActiveSelection)
    }

    @ViewBuilder
    private var editSelectionCommands: some View {
        Button("Select All") {
            model.selectAllItems(on: model.activePaneSide)
        }
        .keyboardShortcut("a", modifiers: [.command])
        .disabled(!model.canSelectAllInActivePane)

        Button("Rename") {
            model.requestInlineRenameActiveSelection()
        }
        .disabled(!model.canRenameActiveSelection)

        Button("Delete") {
            model.trashActiveSelection()
        }
        .keyboardShortcut(.delete, modifiers: [.command])
        .disabled(!model.canTrashActiveSelection)

        Divider()

        Button("Batch Rename…") {
            model.requestBatchRenameDialog(on: model.activePaneSide)
        }
        .keyboardShortcut("m", modifiers: [.control])
        .disabled(!model.canBatchRenameActiveSelection)
    }

    // MARK: - View

    @ViewBuilder
    private var viewDisplayCommands: some View {
        Toggle("Show Hidden Files", isOn: $model.showHiddenFiles)
            .disabled(model.isInlineRenaming)

        Button("Refresh") {
            model.refreshAll()
        }
        .keyboardShortcut("r", modifiers: [.command])
        .disabled(model.isInlineRenaming)
    }

    @ViewBuilder
    private var viewNavigationCommands: some View {
        Button("Focus Left Pane") {
            model.requestPaneFocus(.left, requestID: "menu", source: "menu-focus-left")
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command])

        Button("Focus Right Pane") {
            model.requestPaneFocus(.right, requestID: "menu", source: "menu-focus-right")
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command])

        Button("History Back") {
            model.navigateBack(model.activePaneSide)
        }
        .keyboardShortcut("[", modifiers: [.control])
        .disabled(!model.canNavigateBackActivePane)

        Button("History Forward") {
            model.navigateForward(model.activePaneSide)
        }
        .keyboardShortcut("]", modifiers: [.control])
        .disabled(!model.canNavigateForwardActivePane)

        Button("Go to Parent Folder") {
            model.navigateUp(model.activePaneSide)
        }
        .keyboardShortcut(.upArrow, modifiers: [.command])

        Button("Open Selection") {
            model.openSelectionWithDefaultApp(on: model.activePaneSide)
        }
        .keyboardShortcut("o", modifiers: [.command])
        .disabled(!model.canOpenActiveSelection)

        Button("Quick Look") {
            model.previewSelection(on: model.activePaneSide)
        }
        .keyboardShortcut(.space, modifiers: [])
        .disabled(!model.canQuickLookActiveSelection)

        Button("Calculate Folder Size") {
            model.calculateSelectedFolderSizes(on: model.activePaneSide)
        }
        .keyboardShortcut(.space, modifiers: [.control])
        .disabled(!model.canQuickLookActiveSelection)
    }

    @ViewBuilder
    private var viewToolCommands: some View {
        Button("Keyboard Shortcuts…") {
            model.requestShortcutHelp()
        }
        .keyboardShortcut("/", modifiers: [.command, .shift])
        .disabled(model.isInlineRenaming)

        Divider()

        Button("Filter Current Folder") {
            model.requestFileSearch(on: model.activePaneSide)
        }
        .keyboardShortcut("s", modifiers: [.control])
        .disabled(model.isInlineRenaming)

        Button("Flat View") {
            model.toggleFlatView(on: model.activePaneSide)
        }
        .keyboardShortcut("b", modifiers: [.control])
        .disabled(model.isInlineRenaming)

        Button("Recursive Search…") {
            model.requestGlobalSearchDialog()
        }
        .disabled(model.isInlineRenaming)

        Button("Compare Directories…") {
            model.requestDirectoryComparison()
        }
        .disabled(model.isInlineRenaming)
    }

    // MARK: - Pane

    @ViewBuilder
    private var paneTransferCommands: some View {
        Button("Copy Left Selection to Right") {
            model.copySelection(from: .left)
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
        .disabled(!model.canCopyFromLeftPane)

        Button("Copy Right Selection to Left") {
            model.copySelection(from: .right)
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
        .disabled(!model.canCopyFromRightPane)

        Button("Move Left Selection to Right") {
            model.moveSelection(from: .left)
        }
        .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
        .disabled(!model.canMoveFromLeftPane)

        Button("Move Right Selection to Left") {
            model.moveSelection(from: .right)
        }
        .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
        .disabled(!model.canMoveFromRightPane)
    }

    @ViewBuilder
    private var paneIntegrationCommands: some View {
        Button("Open in Ghostty or Terminal") {
            let side = model.activePaneSide
            model.openInTerminal(model.pane(for: side).selectedItemURLs, on: side)
        }
        .keyboardShortcut("t", modifiers: [.command, .option])
        .disabled(!model.canOpenTerminalActiveSelection)

        Button("Share…") {
            model.shareActiveSelection()
        }
        .disabled(!model.canShareActiveSelection)

        Button("Open in New Tab(s)") {
            let side = model.activePaneSide
            let folders = model.selectedDirectoryURLs(
                in: model.pane(for: side).selectedItemURLs,
                on: side
            )
            model.openSelectionInNewTabs(on: side, folderURLs: folders)
        }
        .disabled(!model.canOpenInNewTabsActiveSelection)

        Button("Add Selection to Favorites") {
            model.addSelectedDirectoriesToFavorites(on: model.activePaneSide)
        }
        .disabled(!model.canAddFavoriteFromActiveSelection)

        Divider()

        Button("Convert Text Encoding to UTF-8") {
            model.convertSelectedTextEncodingToUTF8(on: model.activePaneSide)
        }
        .disabled(!model.canConvertActiveSelectionToUTF8)
    }

    @ViewBuilder
    private var paneArchiveCommands: some View {
        Button("Compress to ZIP") {
            model.compressSelectionToZip(on: model.activePaneSide)
        }
        .disabled(!model.canCompressActiveSelection)

        Button("Extract Here") {
            model.extractArchiveSelection(on: model.activePaneSide, mode: .currentDirectory)
        }
        .disabled(!model.canExtractActiveSelection)

        Button("Extract to Subfolder(s)") {
            model.extractArchiveSelection(on: model.activePaneSide, mode: .namedSubfolder)
        }
        .disabled(!model.canExtractActiveSelection)
    }
}
