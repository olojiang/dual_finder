import Foundation

public enum FileOperationConflictResolution: String, Sendable, CaseIterable {
    case overwrite
    case skip
    case keepBoth
    case largerWins
}

public struct FileOperationOptions: Sendable {
    public var defaultConflictResolution: FileOperationConflictResolution

    public init(defaultConflictResolution: FileOperationConflictResolution = .keepBoth) {
        self.defaultConflictResolution = defaultConflictResolution
    }
}

public struct FileOperationConflict: Sendable, Equatable {
    public let source: URL
    public let destination: URL

    public init(source: URL, destination: URL) {
        self.source = source
        self.destination = destination
    }
}

public struct FileOperationProgress: Sendable, Equatable {
    public let completedBytes: Int64
    public let totalBytes: Int64
    public let completedItems: Int
    public let totalItems: Int
    public let currentItem: URL?
    public let currentItemBytes: Int64?
    public let copiedItems: Int
    public let copiedBytes: Int64
    public let skippedItems: Int
    public let skippedBytes: Int64

    public init(
        completedBytes: Int64,
        totalBytes: Int64,
        completedItems: Int,
        totalItems: Int,
        currentItem: URL?,
        currentItemBytes: Int64? = nil,
        copiedItems: Int = 0,
        copiedBytes: Int64 = 0,
        skippedItems: Int = 0,
        skippedBytes: Int64 = 0
    ) {
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
        self.completedItems = completedItems
        self.totalItems = totalItems
        self.currentItem = currentItem
        self.currentItemBytes = currentItemBytes
        self.copiedItems = copiedItems
        self.copiedBytes = copiedBytes
        self.skippedItems = skippedItems
        self.skippedBytes = skippedBytes
    }

    public var fractionCompleted: Double? {
        if totalBytes > 0 {
            return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
        }
        guard totalItems > 0 else { return nil }
        return min(max(Double(completedItems) / Double(totalItems), 0), 1)
    }
}

public final class FileOperationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}
