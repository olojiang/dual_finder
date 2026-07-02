import AppKit
import DualFinderCore
import Foundation

private nonisolated(unsafe) var frontendInstalledLogger: AppLogging?

enum FrontendLogCapture: @unchecked Sendable {
    private nonisolated(unsafe) static var stderrPipe: Pipe?
    private nonisolated(unsafe) static var preservedStderrFD: Int32 = -1

    static func install(logger: AppLogging) {
        guard frontendInstalledLogger == nil else { return }
        frontendInstalledLogger = logger
        installUncaughtExceptionHandler()
        installStderrCapture()
        logger.info("frontend-log", "capture.installed", metadata: [:])
    }

    private static func installUncaughtExceptionHandler() {
        NSSetUncaughtExceptionHandler(frontendUncaughtExceptionHandler)
    }

    private static func installStderrCapture() {
        let pipe = Pipe()
        stderrPipe = pipe
        preservedStderrFD = dup(STDERR_FILENO)
        guard preservedStderrFD >= 0 else { return }

        setlinebuf(stderr)
        dup2(pipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            guard let text = String(data: data, encoding: .utf8) else { return }
            for line in text.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { continue }
                let level: LogLevel = {
                    let lower = trimmed.lowercased()
                    if lower.contains("error") || lower.contains("failed") || lower.contains("fatal") {
                        return .error
                    }
                    if lower.contains("warn") {
                        return .warning
                    }
                    return .info
                }()
                frontendInstalledLogger?.log(level, "frontend.stderr", trimmed, metadata: [:])
            }
            if preservedStderrFD >= 0, let forward = trimmedData(data) {
                forward.withUnsafeBytes { buffer in
                    guard let base = buffer.baseAddress else { return }
                    _ = write(preservedStderrFD, base, buffer.count)
                }
            }
        }
    }

    private static func trimmedData(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        return data
    }
}

private func frontendUncaughtExceptionHandler(_ exception: NSException) {
    let metadata = [
        "name": exception.name.rawValue,
        "reason": exception.reason ?? "",
        "stack": exception.callStackSymbols.joined(separator: " | ")
    ]
    if let logger = frontendInstalledLogger as? AppLogger {
        logger.logSync(.error, "frontend.exception", "uncaught exception", metadata: metadata)
    } else {
        frontendInstalledLogger?.error(
            "frontend.exception",
            "uncaught exception",
            metadata: metadata
        )
    }
}
