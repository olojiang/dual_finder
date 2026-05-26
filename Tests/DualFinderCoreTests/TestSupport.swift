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

final class CapturingLogger: AppLogging {
    private(set) var messages: [String] = []

    func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String]) {
        messages.append("\(level.rawValue) \(category) \(message) \(metadata)")
    }
}
