import Foundation
@testable import DualFinderCore

final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DualFinderTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

final class CapturingLogger: AppLogging, @unchecked Sendable {
    private let lock = NSLock()
    private var _messages: [String] = []

    var messages: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _messages
    }

    func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String]) {
        lock.lock()
        _messages.append("\(level.rawValue) \(category) \(message) \(metadata)")
        lock.unlock()
    }
}
