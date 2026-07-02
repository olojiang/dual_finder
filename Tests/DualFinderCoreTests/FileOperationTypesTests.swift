import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileOperationTypes")
struct FileOperationTypesTests {
    @Test("defaults to keeping both files on conflicts")
    func defaultsToKeepBothConflictResolution() {
        #expect(FileOperationOptions().defaultConflictResolution == .keepBoth)
        #expect(FileOperationOptions().syncMode == false)
    }

    @Test("exposes largerWins as a conflict resolution option")
    func exposesLargerWinsConflictResolution() {
        #expect(FileOperationConflictResolution.allCases.contains(.largerWins))
    }

    @Test("reports byte based progress before item based progress")
    func reportsByteBasedProgress() {
        let progress = FileOperationProgress(
            completedBytes: 25,
            totalBytes: 100,
            completedItems: 0,
            totalItems: 4,
            currentItem: nil
        )

        #expect(progress.fractionCompleted == 0.25)
    }

    @Test("clamps progress fractions")
    func clampsProgressFractions() {
        let overComplete = FileOperationProgress(
            completedBytes: 150,
            totalBytes: 100,
            completedItems: 0,
            totalItems: 0,
            currentItem: nil
        )
        let negative = FileOperationProgress(
            completedBytes: -5,
            totalBytes: 100,
            completedItems: 0,
            totalItems: 0,
            currentItem: nil
        )

        #expect(overComplete.fractionCompleted == 1)
        #expect(negative.fractionCompleted == 0)
    }

    @Test("falls back to item based progress when byte totals are unavailable")
    func reportsItemBasedProgress() {
        let progress = FileOperationProgress(
            completedBytes: 0,
            totalBytes: 0,
            completedItems: 2,
            totalItems: 4,
            currentItem: URL(fileURLWithPath: "/tmp/current")
        )

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("returns nil progress when no totals are available")
    func returnsNilProgressWithoutTotals() {
        let progress = FileOperationProgress(
            completedBytes: 0,
            totalBytes: 0,
            completedItems: 0,
            totalItems: 0,
            currentItem: nil
        )

        #expect(progress.fractionCompleted == nil)
    }

    @Test("records cancellation state")
    func recordsCancellationState() {
        let cancellation = FileOperationCancellation()

        #expect(!cancellation.isCancelled)
        cancellation.cancel()
        #expect(cancellation.isCancelled)
    }
}
