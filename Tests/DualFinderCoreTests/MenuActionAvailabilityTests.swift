import XCTest
@testable import DualFinderCore

final class MenuActionAvailabilityTests: XCTestCase {
    func testCopyRequiresSelectionAndNotRenaming() {
        XCTAssertTrue(MenuActionAvailability.canCopyFiles(hasSelection: true, isInlineRenaming: false))
        XCTAssertFalse(MenuActionAvailability.canCopyFiles(hasSelection: false, isInlineRenaming: false))
        XCTAssertFalse(MenuActionAvailability.canCopyFiles(hasSelection: true, isInlineRenaming: true))
    }

    func testPasteRequiresPasteboardAndIdleState() {
        XCTAssertTrue(
            MenuActionAvailability.canPasteFiles(
                pasteboardHasFileURLs: true,
                isInlineRenaming: false,
                isArchiveOperationRunning: false
            )
        )
        XCTAssertFalse(
            MenuActionAvailability.canPasteFiles(
                pasteboardHasFileURLs: false,
                isInlineRenaming: false,
                isArchiveOperationRunning: false
            )
        )
        XCTAssertFalse(
            MenuActionAvailability.canPasteFiles(
                pasteboardHasFileURLs: true,
                isInlineRenaming: true,
                isArchiveOperationRunning: false
            )
        )
        XCTAssertFalse(
            MenuActionAvailability.canPasteFiles(
                pasteboardHasFileURLs: true,
                isInlineRenaming: false,
                isArchiveOperationRunning: true
            )
        )
    }

    func testRenameRequiresSingleSelection() {
        XCTAssertTrue(MenuActionAvailability.canRenameSelection(selectionCount: 1, isInlineRenaming: false))
        XCTAssertFalse(MenuActionAvailability.canRenameSelection(selectionCount: 2, isInlineRenaming: false))
        XCTAssertFalse(MenuActionAvailability.canRenameSelection(selectionCount: 1, isInlineRenaming: true))
    }

    func testSelectAllRequiresItems() {
        XCTAssertTrue(MenuActionAvailability.canSelectAll(itemCount: 3, isInlineRenaming: false))
        XCTAssertFalse(MenuActionAvailability.canSelectAll(itemCount: 0, isInlineRenaming: false))
    }

    func testAddFavoriteRequiresDirectoryAndNotAlreadyFavorite() {
        XCTAssertTrue(
            MenuActionAvailability.canAddFavorite(
                hasDirectorySelection: true,
                isAlreadyFavorite: false,
                isInlineRenaming: false
            )
        )
        XCTAssertFalse(
            MenuActionAvailability.canAddFavorite(
                hasDirectorySelection: true,
                isAlreadyFavorite: true,
                isInlineRenaming: false
            )
        )
    }
}
