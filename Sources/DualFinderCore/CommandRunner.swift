import Darwin
import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

public protocol CommandRunning: Sendable {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult
}

public protocol CancellableCommandRunning: CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?
    ) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    private let maxCapturedOutputBytes: Int?

    public init(maxCapturedOutputBytes: Int? = nil) {
        self.maxCapturedOutputBytes = maxCapturedOutputBytes
    }

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult {
        try run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            cancellation: nil
        )
    }
}

extension ProcessCommandRunner: CancellableCommandRunning {
    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?
    ) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workingDirectory {
            process.currentDirectoryURL = workingDirectory
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdout = PipeOutputCapture(pipe: stdoutPipe, maxBytes: maxCapturedOutputBytes)
        let stderr = PipeOutputCapture(pipe: stderrPipe, maxBytes: maxCapturedOutputBytes)
        stdout.start()
        stderr.start()
        defer {
            stdout.stop()
            stderr.stop()
        }

        try process.run()
        while process.isRunning {
            if cancellation?.isCancelled == true {
                process.terminate()
                usleep(200_000)
                if process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                process.waitUntilExit()
                throw FileOperationError.cancelled
            }
            usleep(100_000)
        }

        stdout.stop()
        stderr.stop()
        return CommandResult(
            exitCode: process.terminationStatus,
            stdout: stdout.stringValue,
            stderr: stderr.stringValue
        )
    }
}

private final class PipeOutputCapture: @unchecked Sendable {
    private let pipe: Pipe
    private let maxBytes: Int?
    private let lock = NSLock()
    private var data = Data()
    private var isStopped = false

    init(pipe: Pipe, maxBytes: Int? = nil) {
        self.pipe = pipe
        self.maxBytes = maxBytes
    }

    func start() {
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let next = handle.availableData
            guard !next.isEmpty else { return }
            self?.append(next)
        }
    }

    func stop() {
        lock.lock()
        let shouldStop = !isStopped
        isStopped = true
        lock.unlock()

        guard shouldStop else { return }
        pipe.fileHandleForReading.readabilityHandler = nil
        append(pipe.fileHandleForReading.readDataToEndOfFile())
    }

    var stringValue: String {
        lock.lock()
        let snapshot = data
        lock.unlock()
        return String(data: snapshot, encoding: .utf8) ?? ""
    }

    private func append(_ next: Data) {
        guard !next.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let maxBytes else {
            data.append(next)
            return
        }
        guard data.count < maxBytes else { return }
        let remaining = maxBytes - data.count
        if next.count <= remaining {
            data.append(next)
        } else {
            data.append(next.prefix(remaining))
        }
    }
}
