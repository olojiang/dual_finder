import Foundation
import DualFinderCore

enum QueuedFileOperationKind: String, Sendable {
    case copy
    case move
    case sync
    case trash

    var displayName: String {
        switch self {
        case .copy: "Copy"
        case .move: "Move"
        case .sync: "Sync"
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

    var progressDetailText: String {
        guard let progress else {
            return status == .running ? "Preparing..." : ""
        }

        if progress.rootTotalItems > 0 {
            var parts = ["\(progress.rootCompletedItems)/\(progress.rootTotalItems) item(s)"]
            if let currentItem = progress.currentItem {
                parts.append(currentItem.lastPathComponent)
            }
            if progress.scannedItems > 0, progress.totalBytes == 0, progress.completedItems == 0 {
                parts.append("scanning \(progress.scannedItems) entries")
            } else if progress.totalBytes > 0 {
                parts.append("\(Self.formatBytes(progress.completedBytes)) / \(Self.formatBytes(progress.totalBytes))")
            } else if status == .running {
                parts.append("preparing")
            }
            if let elapsed = progress.elapsedSeconds, elapsed > 0 {
                parts.append("\(Self.formatDecimal(elapsed))s")
            }
            return parts.joined(separator: " • ")
        }

        if progress.scannedItems > 0, progress.totalBytes == 0, progress.completedItems == 0 {
            var parts = ["Scanning \(progress.scannedItems) item(s)"]
            if let currentItem = progress.currentItem {
                parts.append(currentItem.lastPathComponent)
            }
            if let elapsed = progress.elapsedSeconds, elapsed > 0 {
                parts.append("\(Self.formatDecimal(elapsed))s")
            }
            return parts.joined(separator: " • ")
        }

        var parts: [String] = []
        if progress.totalItems > 0 {
            parts.append("\(progress.completedItems)/\(progress.totalItems) item(s)")
        }
        if progress.totalBytes > 0 {
            parts.append("\(Self.formatBytes(progress.completedBytes)) / \(Self.formatBytes(progress.totalBytes))")
        } else if status == .running {
            parts.append("calculating size")
        }
        if progress.copiedItems > 0 || progress.copiedBytes > 0 {
            parts.append("copied \(progress.copiedItems) (\(Self.formatBytes(progress.copiedBytes)))")
        }
        if progress.skippedItems > 0 || progress.skippedBytes > 0 {
            parts.append("skipped \(progress.skippedItems) (\(Self.formatBytes(progress.skippedBytes)))")
        }
        if let itemRate = Self.itemRateText(progress) {
            parts.append(itemRate)
        }
        if let secondsPerMegabyte = Self.secondsPerMegabyteText(progress) {
            parts.append(secondsPerMegabyte)
        }
        if let currentItemBytes = progress.currentItemBytes {
            parts.append("current item \(Self.formatBytes(currentItemBytes))")
        }
        return parts.joined(separator: " • ")
    }

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func itemRateText(_ progress: FileOperationProgress) -> String? {
        guard let elapsed = progress.elapsedSeconds, elapsed > 0, progress.completedItems > 0 else { return nil }
        return "\(formatDecimal(Double(progress.completedItems) / elapsed)) files/s"
    }

    private static func secondsPerMegabyteText(_ progress: FileOperationProgress) -> String? {
        guard let elapsed = progress.elapsedSeconds, elapsed > 0 else { return nil }
        let measuredBytes = progress.copiedBytes > 0 ? progress.copiedBytes : progress.completedBytes
        guard measuredBytes > 0 else { return nil }
        let megabytes = Double(measuredBytes) / 1_000_000
        guard megabytes > 0 else { return nil }
        return "\(formatDecimal(elapsed / megabytes)) s/MB"
    }

    private static func formatDecimal(_ value: Double) -> String {
        if value >= 100 {
            return String(format: "%.0f", value)
        }
        if value >= 10 {
            return String(format: "%.1f", value)
        }
        return String(format: "%.2f", value)
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
    let execution: QueuedFileOperationExecution
    let cancellation: FileOperationCancellation
    let refreshPolicy: FileOperationRefreshPolicy
}

enum QueuedFileOperationExecution: Sendable {
    case local
    case android(AndroidQueuedFileOperation)
}

enum AndroidQueuedFileOperation: Sendable, Equatable {
    case push(localURLs: [URL], remoteDirectory: String, deviceSerial: String, removeLocalAfterCopy: Bool, sync: Bool)
    case pull(remoteURLs: [URL], remotePaths: [String], remoteByteSizes: [Int64?], localDirectory: URL, deviceSerial: String, removeRemoteAfterCopy: Bool, sync: Bool)
    case transfer(remoteURLs: [URL], remotePaths: [String], remoteByteSizes: [Int64?], remoteDirectory: String, deviceSerial: String, move: Bool, sync: Bool)
    case remove(remoteURLs: [URL], remotePaths: [String], remoteByteSizes: [Int64?], deviceSerial: String)

    var itemURLs: [URL] {
        switch self {
        case .push(let localURLs, _, _, _, _):
            localURLs
        case .pull(let remoteURLs, _, _, _, _, _, _),
             .transfer(let remoteURLs, _, _, _, _, _, _),
             .remove(let remoteURLs, _, _, _):
            remoteURLs
        }
    }
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
