import Foundation
import DualFinderCore

enum QueuedFileOperationKind: String, Sendable {
    case copy
    case move
    case trash

    var displayName: String {
        switch self {
        case .copy: "Copy"
        case .move: "Move"
        case .trash: "Trash"
        }
    }
}

enum QueuedFileOperationStatus: String, Sendable {
    case queued
    case running
    case completed
    case failed
    case cancelled
}

struct QueuedFileOperation: Identifiable, Equatable {
    let id: UUID
    let kind: QueuedFileOperationKind
    let sources: [URL]
    let destination: URL?
    var status: QueuedFileOperationStatus
    var progress: FileOperationProgress?
    var message: String

    var fractionCompleted: Double? {
        progress?.fractionCompleted
    }

    var title: String {
        "\(kind.displayName) \(sources.count) item(s)"
    }
}

struct FileConflictDialogRequest: Identifiable, Equatable {
    let id = UUID()
    let source: URL
    let destination: URL
}

struct DirectoryComparisonDialogRequest: Identifiable, Equatable {
    let id = UUID()
}

struct GlobalSearchDialogRequest: Identifiable, Equatable {
    let id = UUID()
}

struct QueuedFileOperationRequest {
    let id: UUID
    let kind: QueuedFileOperationKind
    let sources: [URL]
    let destination: URL?
    let cancellation: FileOperationCancellation
}

struct FileConflictAnswer: Sendable {
    let resolution: FileOperationConflictResolution
    let applyToAll: Bool
}

final class FileConflictAnswerBox: @unchecked Sendable {
    private let lock = NSLock()
    private let semaphore = DispatchSemaphore(value: 0)
    private var answer: FileConflictAnswer?

    func resolve(_ answer: FileConflictAnswer) {
        lock.lock()
        self.answer = answer
        lock.unlock()
        semaphore.signal()
    }

    func wait() -> FileConflictAnswer {
        semaphore.wait()
        lock.lock()
        defer { lock.unlock() }
        return answer ?? FileConflictAnswer(resolution: .keepBoth, applyToAll: false)
    }
}
