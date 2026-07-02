import Foundation
import Testing
@testable import DualFinderCore

@Suite("FileOperationProgressCoalescer")
struct FileOperationProgressCoalescerTests {
    @Test("coalesces rapid updates into one flush")
    func coalescesRapidUpdates() async throws {
        let flushed = Locked(false)
        let coalescer = FileOperationProgressCoalescer(flushDelay: 0.05) { _ in
            flushed.withLock { $0 = true }
        }
        let id = UUID()
        coalescer.record(sampleProgress(completedItems: 1), for: id)
        coalescer.record(sampleProgress(completedItems: 2), for: id)

        let deadline = Date().addingTimeInterval(1)
        while Date() < deadline, !flushed.value {
            try await Task.sleep(nanoseconds: 20_000_000)
        }

        #expect(flushed.value)
        #expect(coalescer.take(for: id)?.completedItems == 2)
    }

    @Test("take returns latest recorded progress")
    func takeReturnsLatestRecordedProgress() {
        let coalescer = FileOperationProgressCoalescer { _ in }
        let id = UUID()
        coalescer.record(sampleProgress(completedItems: 1), for: id)
        coalescer.record(sampleProgress(completedItems: 9), for: id)
        #expect(coalescer.take(for: id)?.completedItems == 9)
    }

    @Test("cancel clears pending progress")
    func cancelClearsPendingProgress() {
        let coalescer = FileOperationProgressCoalescer { _ in }
        let id = UUID()
        coalescer.record(sampleProgress(completedItems: 3), for: id)
        coalescer.cancel(id)
        #expect(coalescer.take(for: id) == nil)
    }

    private func sampleProgress(completedItems: Int) -> FileOperationProgress {
        FileOperationProgress(
            completedBytes: 0,
            totalBytes: 0,
            completedItems: completedItems,
            totalItems: 10,
            currentItem: nil,
            copiedItems: 0,
            copiedBytes: 0,
            skippedItems: 0,
            skippedBytes: 0,
            rootCompletedItems: 0,
            rootTotalItems: 1,
            elapsedSeconds: 0
        )
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ storage: Value) {
        self.storage = storage
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func withLock(_ body: (inout Value) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        body(&storage)
    }
}