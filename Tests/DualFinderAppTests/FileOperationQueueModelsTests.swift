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
                currentItem: nil
            ),
            message: "Copying",
            finishedAt: nil
        )

        #expect(operation.title == "Copy 2 item(s)")
        #expect(operation.fractionCompleted == 0.5)
        #expect(QueuedFileOperationKind.move.displayName == "Move")
        #expect(QueuedFileOperationKind.trash.displayName == "Trash")
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
}
