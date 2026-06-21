import Foundation

public enum LogLevel: String, Sendable {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public protocol AppLogging: AnyObject, Sendable {
    func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String])
}

public extension AppLogging {
    func debug(_ category: String, _ message: String, metadata: [String: String] = [:]) {
        log(.debug, category, message, metadata: metadata)
    }

    func info(_ category: String, _ message: String, metadata: [String: String] = [:]) {
        log(.info, category, message, metadata: metadata)
    }

    func warning(_ category: String, _ message: String, metadata: [String: String] = [:]) {
        log(.warning, category, message, metadata: metadata)
    }

    func error(_ category: String, _ message: String, metadata: [String: String] = [:]) {
        log(.error, category, message, metadata: metadata)
    }
}

public final class RotatingLogStore: @unchecked Sendable {
    private let directory: URL
    private let calendar: Calendar
    private let dateProvider: () -> Date
    private let fileManager: FileManager
    private let lock = NSLock()
    private let timestampFormatter: DateFormatter
    private let dayFormatter: DateFormatter

    public init(
        directory: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("DualFinder", isDirectory: true),
        calendar: Calendar = Calendar(identifier: .gregorian),
        dateProvider: @escaping () -> Date = Date.init,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.calendar = calendar
        self.dateProvider = dateProvider
        self.fileManager = fileManager

        timestampFormatter = DateFormatter()
        timestampFormatter.calendar = calendar
        timestampFormatter.locale = Locale(identifier: "en_US_POSIX")
        timestampFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"

        dayFormatter = DateFormatter()
        dayFormatter.calendar = calendar
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyy-MM-dd"
    }

    public var logDirectory: URL {
        directory
    }

    public func append(level: LogLevel, category: String, message: String, metadata: [String: String] = [:]) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let now = dateProvider()
        let line = formatLine(date: now, level: level, category: category, message: message, metadata: metadata)
        let fileURL = directory.appendingPathComponent("\(dayFormatter.string(from: now)).log")

        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            if let data = line.data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } else {
            try line.write(to: fileURL, atomically: true, encoding: .utf8)
        }

        try pruneLogs()
    }

    private func formatLine(date: Date, level: LogLevel, category: String, message: String, metadata: [String: String]) -> String {
        var parts = [
            timestampFormatter.string(from: date),
            level.rawValue,
            "[\(category)]",
            message
        ]
        if !metadata.isEmpty {
            let metadataText = metadata
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: " ")
            parts.append(metadataText)
        }
        return parts.joined(separator: " ") + "\n"
    }

    private func pruneLogs() throws {
        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "log" && $0.deletingPathExtension().lastPathComponent.count == 10 }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard files.count > 7 else { return }
        for file in files.prefix(files.count - 7) {
            try fileManager.removeItem(at: file)
        }
    }
}

public final class AppLogger: AppLogging, @unchecked Sendable {
    private let store: RotatingLogStore
    private let queue = DispatchQueue(label: "com.dualfinder.app-logger", qos: .utility)

    public init(store: RotatingLogStore = RotatingLogStore()) {
        self.store = store
    }

    public var logDirectory: URL {
        store.logDirectory
    }

    public func log(_ level: LogLevel, _ category: String, _ message: String, metadata: [String: String] = [:]) {
        queue.async { [store] in
            do {
                try store.append(level: level, category: category, message: message, metadata: metadata)
            } catch {
                fputs("DualFinder log write failed: \(error)\n", stderr)
            }
        }
    }
}
