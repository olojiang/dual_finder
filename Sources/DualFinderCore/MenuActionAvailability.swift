import Foundation

/// Rules for enabling menu bar items based on selection, pane state, and pasteboard content.
public enum MenuActionAvailability {
    public static func canCopyFiles(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canPasteFiles(
        pasteboardHasFileURLs: Bool,
        isInlineRenaming: Bool,
        isArchiveOperationRunning: Bool
    ) -> Bool {
        pasteboardHasFileURLs && !isInlineRenaming && !isArchiveOperationRunning
    }

    public static func canTrashSelection(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canEmptyTrash(isInlineRenaming: Bool, isArchiveOperationRunning: Bool) -> Bool {
        !isInlineRenaming && !isArchiveOperationRunning
    }

    public static func canOpenSelection(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canQuickLook(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canRenameSelection(selectionCount: Int, isInlineRenaming: Bool) -> Bool {
        selectionCount == 1 && !isInlineRenaming
    }

    public static func canSelectAll(itemCount: Int, isInlineRenaming: Bool) -> Bool {
        itemCount > 0 && !isInlineRenaming
    }

    public static func canCopyAbsolutePath(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canBatchRename(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canExtractFilenameFromContent(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canTransferToOtherPane(
        hasSelection: Bool,
        isInlineRenaming: Bool,
        isArchiveOperationRunning: Bool
    ) -> Bool {
        hasSelection && !isInlineRenaming && !isArchiveOperationRunning
    }

    public static func canShare(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canOpenInTerminal(hasSelection: Bool, isInlineRenaming: Bool) -> Bool {
        hasSelection && !isInlineRenaming
    }

    public static func canCreateItems(isInlineRenaming: Bool, isArchiveOperationRunning: Bool) -> Bool {
        !isInlineRenaming && !isArchiveOperationRunning
    }

    public static func canNavigateHistory(canNavigate: Bool, isInlineRenaming: Bool) -> Bool {
        canNavigate && !isInlineRenaming
    }

    public static func canAddFavorite(
        hasDirectorySelection: Bool,
        isAlreadyFavorite: Bool,
        isInlineRenaming: Bool
    ) -> Bool {
        hasDirectorySelection && !isAlreadyFavorite && !isInlineRenaming
    }
}
