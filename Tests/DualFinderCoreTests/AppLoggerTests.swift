import Foundation
import Testing
@testable import DualFinderCore

@Suite("AppLogger")
struct AppLoggerTests {
    @Test("drops debug logs when pending queue is full")
    func dropsDebugLogsWhenPendingQueueIsFull() async throws {
        let root = try TemporaryDirectory()
        let store = RotatingLogStore(directory: root.url)
        let logger = AppLogger(store: store, maxPendingLogs: 2)

        for index in 0..<20 {
            logger.debug("file-operation", "sync.skip-identical", metadata: ["index": "\(index)"])
        }
        logger.info("file-operation", "sync.skip-progress", metadata: ["skippedItems": "1"])

        try await Task.sleep(nanoseconds: 300_000_000)

        let contents = try String(contentsOf: root.url.appendingPathComponent(logFileName(in: root.url)), encoding: .utf8)
        let debugIdenticalCount = contents.components(separatedBy: "sync.skip-identical").count - 1
        #expect(contents.contains("debug.logs.dropped"))
        #expect(contents.contains("sync.skip-progress"))
        #expect(debugIdenticalCount <= 2)
    }

    private func logFileName(in directory: URL) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: Date())).log"
    }
}
