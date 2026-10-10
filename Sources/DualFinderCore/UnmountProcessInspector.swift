import Foundation

public struct UnmountProcessBlocker: Sendable, Equatable, Identifiable {
    public let processID: Int
    public let processName: String
    public let openPaths: [String]
    public let executablePath: String?
    public let userName: String?

    public var id: Int { processID }

    public init(
        processID: Int,
        processName: String,
        openPaths: [String],
        executablePath: String? = nil,
        userName: String? = nil
    ) {
        self.processID = processID
        self.processName = processName
        self.openPaths = openPaths
        self.executablePath = executablePath
        self.userName = userName
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
            return addingProcessDetails(to: blockers)
        }
        if result.exitCode == 1, result.stderr.isEmpty { return [] }
        throw UnmountProcessInspectorError.commandFailed(result.stderr)
    }

    private func addingProcessDetails(to blockers: [UnmountProcessBlocker]) -> [UnmountProcessBlocker] {
        guard !blockers.isEmpty else { return [] }
        let processIDs = blockers.map { String($0.processID) }.joined(separator: ",")
        guard let result = try? commandRunner.run(
            executable: "/bin/ps",
            arguments: ["-p", processIDs, "-o", "pid=", "-o", "user=", "-o", "comm="],
            workingDirectory: nil
        ) else { return blockers }
        guard result.succeeded else { return blockers }

        let details = Self.parseProcessDetails(result.stdout)
        return blockers.map { blocker in
            guard let detail = details[blocker.processID] else { return blocker }
            return UnmountProcessBlocker(
                processID: blocker.processID,
                processName: blocker.processName,
                openPaths: blocker.openPaths,
                executablePath: detail.executablePath,
                userName: detail.userName
            )
        }
    }

    private static func parseProcessDetails(_ output: String) -> [Int: ProcessDetails] {
        output.split(whereSeparator: \.isNewline).reduce(into: [:]) { details, line in
            let fields = line.split(maxSplits: 2, omittingEmptySubsequences: true, whereSeparator: \.isWhitespace)
            guard fields.count == 3, let processID = Int(fields[0]) else { return }
            details[processID] = ProcessDetails(userName: String(fields[1]), executablePath: String(fields[2]))
        }
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

    private struct ProcessDetails {
        let userName: String
        let executablePath: String
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
