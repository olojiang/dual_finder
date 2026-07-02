import Foundation

/// Coalesces high-frequency file-operation progress callbacks before UI updates.
public final class FileOperationProgressCoalescer: @unchecked Sendable {
    private let lock = NSLock()
    private let flushDelay: TimeInterval
    private let flushHandler: @Sendable (UUID) -> Void
    private var coalescedProgress: [UUID: FileOperationProgress] = [:]
    private var scheduledFlushes: Set<UUID> = []

    public init(
        flushDelay: TimeInterval = 0.5,
        flushHandler: @escaping @Sendable (UUID) -> Void
    ) {
        self.flushDelay = flushDelay
        self.flushHandler = flushHandler
    }

    public func record(_ progress: FileOperationProgress, for id: UUID) {
        lock.lock()
        coalescedProgress[id] = progress
        let shouldSchedule = !scheduledFlushes.contains(id)
        if shouldSchedule {
            scheduledFlushes.insert(id)
        }
        lock.unlock()

        guard shouldSchedule else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + flushDelay) { [weak self] in
            self?.flushHandler(id)
        }
    }

    public func take(for id: UUID) -> FileOperationProgress? {
        lock.lock()
        scheduledFlushes.remove(id)
        let progress = coalescedProgress.removeValue(forKey: id)
        lock.unlock()
        return progress
    }

    public func cancel(_ id: UUID) {
        lock.lock()
        coalescedProgress.removeValue(forKey: id)
        scheduledFlushes.remove(id)
        lock.unlock()
    }
}
