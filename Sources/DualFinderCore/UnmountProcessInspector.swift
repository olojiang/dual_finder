import Foundation

public struct UnmountProcessBlocker: Sendable, Equatable, Identifiable {
    public let processID: Int
    public let processName: String
    public let openPaths: [String]

    public var id: Int { processID }

    public init(processID: Int, processName: String, openPaths: [String]) {
        self.processID = processID
        self.processName = processName
        self.openPaths = openPaths
    }
}

public struct UnmountProcessInspector: Sendable {
    private let commandRunner: any CommandRunning

    public init(commandRunner: any CommandRunning = ProcessCommandRunner(maxCapturedOutputBytes: 1_048_576)) {
        self.commandRunner = commandRunner
    }

    public func inspect(mountPoint: URL) throws -> [UnmountProcessBlocker] {
        let path = mountPoint.standardizedFileURL.path
        let result = try commandRunner.run(
            executable: "/usr/sbin/lsof",
            arguments: ["-nP", "-Fpcn", "+f", "--", path],
            workingDirectory: nil
        )
        let blockers = Self.parse(result.stdout)
        if result.succeeded || !blockers.isEmpty {
            return blockers
        }
        if result.exitCode == 1, result.stderr.isEmpty { return [] }
        throw UnmountProcessInspectorError.commandFailed(result.stderr)
    }

    private static func parse(_ output: String) -> [UnmountProcessBlocker] {
        var blockers: [UnmountProcessBlocker] = []
        var processID: Int?
        var processName = "Unknown process"
        var paths: [String] = []

        func appendCurrent() {
            guard let processID, !paths.isEmpty else { return }
            blockers.append(UnmountProcessBlocker(
                processID: processID,
                processName: processName,
                openPaths: paths
            ))
        }

        for field in output.split(whereSeparator: \.isNewline) {
            guard let prefix = field.first else { continue }
            let value = String(field.dropFirst())
            switch prefix {
            case "p":
                appendCurrent()
                processID = Int(value)
                processName = "Unknown process"
                paths = []
            case "c":
                processName = value
            case "n":
                if !paths.contains(value) { paths.append(value) }
            default:
                continue
            }
        }
        appendCurrent()
        return blockers.sorted {
            ($0.processName, $0.processID) < ($1.processName, $1.processID)
        }
    }
}

public enum UnmountProcessInspectorError: LocalizedError, Equatable {
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .commandFailed(detail):
            detail.isEmpty ? "Could not inspect open files on the volume." : detail
        }
    }
}
