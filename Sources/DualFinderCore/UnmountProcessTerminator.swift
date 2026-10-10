import Foundation

public struct UnmountProcessTerminator: Sendable {
    private let commandRunner: any CommandRunning
    private let inspector: UnmountProcessInspector

    public init(commandRunner: any CommandRunning = ProcessCommandRunner()) {
        self.commandRunner = commandRunner
        inspector = UnmountProcessInspector(commandRunner: commandRunner)
    }

    public func terminate(_ blocker: UnmountProcessBlocker, on mountPoint: URL) throws {
        guard blocker.processID > 1,
              blocker.processID != Int(ProcessInfo.processInfo.processIdentifier) else {
            throw UnmountProcessTerminationError.protectedProcess
        }
        guard let current = try inspector.inspect(mountPoint: mountPoint)
            .first(where: { $0.processID == blocker.processID }) else {
            throw UnmountProcessTerminationError.noLongerBlocking
        }
        guard hasSameIdentity(current, as: blocker) else {
            throw UnmountProcessTerminationError.processChanged
        }

        let result = try commandRunner.run(
            executable: "/bin/kill",
            arguments: ["-KILL", String(blocker.processID)],
            workingDirectory: nil
        )
        guard result.succeeded else {
            throw UnmountProcessTerminationError.commandFailed(result.stderr)
        }
    }

    private func hasSameIdentity(_ current: UnmountProcessBlocker, as original: UnmountProcessBlocker) -> Bool {
        current.processName == original.processName
            && (original.userName == nil || current.userName == original.userName)
            && (original.executablePath == nil || current.executablePath == original.executablePath)
    }
}

public enum UnmountProcessTerminationError: LocalizedError, Equatable {
    case protectedProcess
    case noLongerBlocking
    case processChanged
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .protectedProcess:
            "The application cannot terminate its own process or a protected system process."
        case .noLongerBlocking:
            "This process no longer appears to be using the volume."
        case .processChanged:
            "The process identity changed. Refresh the unmount details before trying again."
        case let .commandFailed(detail):
            detail.isEmpty ? "Could not force terminate this process." : detail
        }
    }
}
