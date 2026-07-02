import Foundation
import Testing
@testable import DualFinderApp
@testable import DualFinderCore

@Suite("FileOperationQueueModels")
struct FileOperationQueueModelsTests {
    @Test("operation titles and progress reflect model state")
    func operationTitlesAndProgressReflectState() {
        let operation = QueuedFileOperation(
            id: UUID(),
            kind: .copy,
            sources: [
                URL(fileURLWithPath: "/tmp/a.txt"),
                URL(fileURLWithPath: "/tmp/b.txt")
            ],
            destination: URL(fileURLWithPath: "/tmp/out", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 10),
            status: .running,
            progress: FileOperationProgress(
                completedBytes: 5,
                totalBytes: 10,
                completedItems: 1,
                totalItems: 2,
                currentItem: nil,
                currentItemBytes: 3,
                elapsedSeconds: 2
            ),
            message: "Copying",
            finishedAt: nil
        )

        #expect(operation.title == "Copy 2 item(s)")
        #expect(operation.fractionCompleted == 0.5)
        #expect(operation.progressDetailText.contains("1/2 item(s)"))
        #expect(operation.progressDetailText.contains("0.50 files/s"))
        #expect(operation.progressDetailText.contains("s/MB"))
        #expect(operation.progressDetailText.contains("current"))
        #expect(QueuedFileOperationKind.move.displayName == "Move")
        #expect(QueuedFileOperationKind.sync.displayName == "Sync")
        #expect(QueuedFileOperationKind.trash.displayName == "Trash")
    }

    @Test("progress detail includes copied and skipped counts with sizes")
    func progressDetailIncludesCopiedAndSkippedCountsWithSizes() {
        let operation = QueuedFileOperation(
            id: UUID(),
            kind: .sync,
            sources: [URL(fileURLWithPath: "/tmp/books")],
            destination: URL(fileURLWithPath: "/tmp/out", isDirectory: true),
            createdAt: Date(timeIntervalSince1970: 10),
            status: .running,
            progress: FileOperationProgress(
                completedBytes: 3_072,
                totalBytes: 4_096,
                completedItems: 3,
                totalItems: 4,
                currentItem: URL(fileURLWithPath: "/tmp/books/current.txt"),
                currentItemBytes: 1_024,
                copiedItems: 1,
                copiedBytes: 2_048,
                skippedItems: 2,
                skippedBytes: 1_024,
                elapsedSeconds: 1
            ),
            message: "current.txt",
            finishedAt: nil
        )

        #expect(operation.progressDetailText.contains("3/4 item(s)"))
        #expect(operation.progressDetailText.contains("copied 1"))
        #expect(operation.progressDetailText.contains("skipped 2"))
        #expect(operation.progressDetailText.contains("3.00 files/s"))
    }

    @Test("refresh policy can defer only successful directory refreshes")
    func refreshPolicyCanDeferOnlySuccessfulDirectoryRefreshes() {
        #expect(FileOperationRefreshPolicy.refreshWhenFinished.shouldRefresh(status: .completed))
        #expect(FileOperationRefreshPolicy.refreshWhenFinished.shouldRefresh(status: .failed))
        #expect(!FileOperationRefreshPolicy.deferSuccessfulRefresh.shouldRefresh(status: .completed))
        #expect(FileOperationRefreshPolicy.deferSuccessfulRefresh.shouldRefresh(status: .failed))
        #expect(FileOperationRefreshPolicy.deferSuccessfulRefresh.shouldRefresh(status: .cancelled))
        #expect(FileOperationRefreshPolicy.trashPolicy(isSimilarFileReviewActive: true) == .deferSuccessfulRefresh)
        #expect(FileOperationRefreshPolicy.trashPolicy(isSimilarFileReviewActive: false) == .refreshWhenFinished)
    }

    @Test("conflict answer box returns resolved answer")
    func conflictAnswerBoxReturnsResolvedAnswer() {
        let box = FileConflictAnswerBox()

        DispatchQueue.global().async {
            box.resolve(FileConflictAnswer(resolution: .overwrite, applyToAll: true))
        }

        let answer = box.wait()

        #expect(answer.resolution == .overwrite)
        #expect(answer.applyToAll)
    }

    @Test("conflict previews show per-file largerWins outcome")
    func conflictPreviewsShowPerFileLargerWinsOutcome() throws {
        let root = try AppTemporaryDirectory()
        let destination = root.url.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let largerSource = root.url.appendingPathComponent("larger.txt")
        let smallerSource = root.url.appendingPathComponent("smaller.txt")
        let missingDestinationSource = root.url.appendingPathComponent("new.txt")
        try Data(repeating: 1, count: 128).write(to: largerSource)
        try Data(repeating: 2, count: 32).write(to: destination.appendingPathComponent("larger.txt"))
        try Data(repeating: 3, count: 16).write(to: smallerSource)
        try Data(repeating: 4, count: 64).write(to: destination.appendingPathComponent("smaller.txt"))
        try Data(repeating: 5, count: 8).write(to: missingDestinationSource)

        let previews = DualFinderViewModel.fileConflictPreviews(
            for: [largerSource, smallerSource, missingDestinationSource],
            destinationDirectory: destination
        )

        #expect(previews.count == 2)
        #expect(previews[0].source == largerSource)
        #expect(previews[0].largerWinsResolution == .overwrite)
        #expect(previews[1].source == smallerSource)
        #expect(previews[1].largerWinsResolution == .skip)
    }

    @Test("scanning progress shows scanned item count")
    func scanningProgressShowsScannedItemCount() {
        let operation = QueuedFileOperation(
            id: UUID(),
            kind: .move,
            sources: [URL(fileURLWithPath: "/tmp/big-folder", isDirectory: true)],
            destination: URL(fileURLWithPath: "/tmp/out", isDirectory: true),
            createdAt: Date(),
            status: .running,
            progress: FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: 0,
                totalItems: 0,
                currentItem: URL(fileURLWithPath: "/tmp/big-folder/nested.bin"),
                scannedItems: 250,
                elapsedSeconds: 3.5
            ),
            message: "Running",
            finishedAt: nil
        )

        #expect(operation.progressDetailText.contains("Scanning 250 item(s)"))
        #expect(operation.progressDetailText.contains("nested.bin"))
    }

    @Test("root progress shows selected item counts")
    func rootProgressShowsSelectedItemCounts() {
        let operation = QueuedFileOperation(
            id: UUID(),
            kind: .move,
            sources: [
                URL(fileURLWithPath: "/tmp/a"),
                URL(fileURLWithPath: "/tmp/b"),
                URL(fileURLWithPath: "/tmp/c")
            ],
            destination: URL(fileURLWithPath: "/tmp/out", isDirectory: true),
            createdAt: Date(),
            status: .running,
            progress: FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: 0,
                totalItems: 0,
                currentItem: URL(fileURLWithPath: "/tmp/b"),
                scannedItems: 1200,
                rootCompletedItems: 1,
                rootTotalItems: 3,
                elapsedSeconds: 2
            ),
            message: "b",
            finishedAt: nil
        )

        #expect(operation.progressDetailText.contains("1/3 item(s)"))
        #expect(operation.progressDetailText.contains("b"))
        #expect(operation.progressDetailText.contains("scanning 1200 entries"))
    }

    @Test("root progress without scan data shows scanning folder")
    func rootProgressWithoutScanDataShowsScanningFolder() {
        let operation = QueuedFileOperation(
            id: UUID(),
            kind: .move,
            sources: [URL(fileURLWithPath: "/tmp/big-folder", isDirectory: true)],
            destination: URL(fileURLWithPath: "/tmp/out", isDirectory: true),
            createdAt: Date(),
            status: .running,
            progress: FileOperationProgress(
                completedBytes: 0,
                totalBytes: 0,
                completedItems: 0,
                totalItems: 0,
                currentItem: URL(fileURLWithPath: "/tmp/big-folder"),
                rootCompletedItems: 0,
                rootTotalItems: 1,
                elapsedSeconds: 0
            ),
            message: "big-folder",
            finishedAt: nil
        )

        #expect(operation.progressDetailText.contains("scanning folder"))
        #expect(!operation.progressDetailText.contains("preparing"))
    }
}

private final class AppTemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DualFinderAppTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
