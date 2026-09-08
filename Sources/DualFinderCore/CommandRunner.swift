import Darwin
import Foundation

public struct CommandResult: Sendable, Equatable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public var succeeded: Bool { exitCode == 0 }
}

public enum CommandOutputChannel: Sendable {
    case stdout
    case stderr
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

public protocol StreamingCommandRunning: CommandRunning {
    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?,
        output: @escaping @Sendable (CommandOutputChannel, String) -> Void
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

extension ProcessCommandRunner: CancellableCommandRunning, StreamingCommandRunning {
    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?
    ) throws -> CommandResult {
        try run(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            cancellation: cancellation,
            output: { _, _ in }
        )
    }

    public func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        cancellation: FileOperationCancellation?,
        output: @escaping @Sendable (CommandOutputChannel, String) -> Void
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

        let stdout = PipeOutputCapture(pipe: stdoutPipe, maxBytes: maxCapturedOutputBytes) { data in
            output(.stdout, String(decoding: data, as: UTF8.self))
        }
        let stderr = PipeOutputCapture(pipe: stderrPipe, maxBytes: maxCapturedOutputBytes) { data in
            output(.stderr, String(decoding: data, as: UTF8.self))
        }
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
    private let onChunk: (@Sendable (Data) -> Void)?
    private let lock = NSLock()
    private var data = Data()
    private var isStopped = false

    init(
        pipe: Pipe,
        maxBytes: Int? = nil,
        onChunk: (@Sendable (Data) -> Void)? = nil
    ) {
        self.pipe = pipe
        self.maxBytes = maxBytes
        self.onChunk = onChunk
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
        onChunk?(next)
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
