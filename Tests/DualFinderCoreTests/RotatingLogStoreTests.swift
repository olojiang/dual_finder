import Foundation
import Testing
@testable import DualFinderCore

@Suite("RotatingLogStore")
struct RotatingLogStoreTests {
    @Test("appends messages to the same daily log without truncating previous content")
    func appendsDailyLog() throws {
        let root = try TemporaryDirectory()
        let store = RotatingLogStore(
            directory: root.url,
            calendar: Calendar(identifier: .gregorian),
            dateProvider: { Date(timeIntervalSince1970: 1_704_067_200) }
        )

        try store.append(level: .info, category: "test", message: "first launch")
        try store.append(level: .info, category: "test", message: "second launch")

        let log = try String(contentsOf: root.url.appendingPathComponent("2024-01-01.log"), encoding: .utf8)
        #expect(log.contains("first launch"))
        #expect(log.contains("second launch"))
    }

    @Test("keeps only the newest seven daily log files")
    func prunesOldDailyLogs() throws {
        let root = try TemporaryDirectory()
        for day in 1...9 {
            let name = "2024-01-\(String(format: "%02d", day)).log"
            try "old \(day)".write(to: root.url.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        let store = RotatingLogStore(
            directory: root.url,
            calendar: Calendar(identifier: .gregorian),
            dateProvider: { Date(timeIntervalSince1970: 1_704_844_800) }
        )

        try store.append(level: .info, category: "test", message: "today")

        let names = try FileManager.default.contentsOfDirectory(atPath: root.url.path).sorted()
        #expect(names == [
            "2024-01-04.log",
            "2024-01-05.log",
            "2024-01-06.log",
            "2024-01-07.log",
            "2024-01-08.log",
            "2024-01-09.log",
            "2024-01-10.log"
        ])
    }

    @Test("AppLogger logSync writes immediately without async delay")
    func appLoggerLogSync() throws {
        let root = try TemporaryDirectory()
        let store = RotatingLogStore(
            directory: root.url,
            calendar: Calendar(identifier: .gregorian),
            dateProvider: { Date(timeIntervalSince1970: 1_704_067_200) }
        )
        let logger = AppLogger(store: store)
        logger.logSync(.warning, "frontend.stderr", "sync warning line")
        let log = try String(contentsOf: root.url.appendingPathComponent("2024-01-01.log"), encoding: .utf8)
        #expect(log.contains("sync warning line"))
        #expect(log.contains("WARN"))
        #expect(log.contains("[frontend.stderr]"))
    }
}
