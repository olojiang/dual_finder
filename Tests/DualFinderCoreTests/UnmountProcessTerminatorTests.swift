import Foundation
import Testing
@testable import DualFinderCore

@Suite("UnmountProcessTerminator")
struct UnmountProcessTerminatorTests {
    @Test("force terminates the selected process after confirming it still blocks the volume")
    func terminatesSelectedBlocker() throws {
        let runner = RecordingCommandRunner(results: [
            .init(exitCode: 0, stdout: "p412\ncgit\nn/Volumes/Media/repo/.git/index\n", stderr: ""),
            .init(exitCode: 0, stdout: "  412 hunter /usr/bin/git\n", stderr: ""),
            .init(exitCode: 0, stdout: "", stderr: "")
        ])
        let terminator = UnmountProcessTerminator(commandRunner: runner)
        let blocker = UnmountProcessBlocker(
            processID: 412,
            processName: "git",
            openPaths: ["/Volumes/Media/repo/.git/index"],
            executablePath: "/usr/bin/git",
            userName: "hunter"
        )

        try terminator.terminate(blocker, on: URL(fileURLWithPath: "/Volumes/Media"))

        #expect(runner.calls.map(\.executable) == ["/usr/sbin/lsof", "/bin/ps", "/bin/kill"])
        #expect(runner.calls.last?.arguments == ["-KILL", "412"])
    }

    @Test("does not kill a process that no longer blocks the volume")
    func skipsProcessThatStoppedBlocking() {
        let runner = RecordingCommandRunner(results: [.init(exitCode: 1, stdout: "", stderr: "")])
        let terminator = UnmountProcessTerminator(commandRunner: runner)
        let blocker = UnmountProcessBlocker(processID: 412, processName: "git", openPaths: ["/Volumes/Media/repo/.git/index"])

        #expect(throws: UnmountProcessTerminationError.noLongerBlocking) {
            try terminator.terminate(blocker, on: URL(fileURLWithPath: "/Volumes/Media"))
        }
        #expect(runner.calls.map(\.executable) == ["/usr/sbin/lsof"])
    }

    @Test("does not kill a reused PID when its process identity changed")
    func skipsChangedProcessIdentity() {
        let runner = RecordingCommandRunner(results: [
            .init(exitCode: 0, stdout: "p412\ncgit\nn/Volumes/Media/other\n", stderr: ""),
            .init(exitCode: 0, stdout: "  412 hunter /usr/bin/python3\n", stderr: "")
        ])
        let terminator = UnmountProcessTerminator(commandRunner: runner)
        let blocker = UnmountProcessBlocker(
            processID: 412,
            processName: "git",
            openPaths: ["/Volumes/Media/repo/.git/index"],
            executablePath: "/usr/bin/git",
            userName: "hunter"
        )

        #expect(throws: UnmountProcessTerminationError.processChanged) {
            try terminator.terminate(blocker, on: URL(fileURLWithPath: "/Volumes/Media"))
        }
        #expect(runner.calls.map(\.executable) == ["/usr/sbin/lsof", "/bin/ps"])
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call {
        let executable: String
        let arguments: [String]
    }

    private var results: [CommandResult]
    private(set) var calls: [Call] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(executable: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
        calls.append(Call(executable: executable, arguments: arguments))
        return results.removeFirst()
    }
}
