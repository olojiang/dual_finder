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

enum FileOperationRefreshPolicy: Sendable {
    case refreshWhenFinished
    case deferSuccessfulRefresh

    static func trashPolicy(isSimilarFileReviewActive: Bool) -> FileOperationRefreshPolicy {
        isSimilarFileReviewActive ? .deferSuccessfulRefresh : .refreshWhenFinished
    }

    var logValue: String {
        switch self {
        case .refreshWhenFinished:
            return "refreshWhenFinished"
        case .deferSuccessfulRefresh:
            return "deferSuccessfulRefresh"
        }
    }

    func shouldRefresh(status: QueuedFileOperationStatus) -> Bool {
        switch self {
        case .refreshWhenFinished:
            return true
        case .deferSuccessfulRefresh:
            return status != .completed
        }
    }
}

struct QueuedFileOperation: Identifiable, Equatable {
    let id: UUID
    let kind: QueuedFileOperationKind
    let sources: [URL]
    let destination: URL?
    let createdAt: Date
    var status: QueuedFileOperationStatus
    var progress: FileOperationProgress?
    var message: String
    var finishedAt: Date?

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
    let conflicts: [FileConflictPreview]
}

struct FileConflictPreview: Identifiable, Equatable, Sendable {
    let source: URL
    let destination: URL
    let sourceSize: Int64?
    let destinationSize: Int64?
    let largerWinsResolution: FileOperationConflictResolution

    var id: String {
        "\(source.path)\u{1F}\(destination.path)"
    }
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
    let refreshPolicy: FileOperationRefreshPolicy
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
