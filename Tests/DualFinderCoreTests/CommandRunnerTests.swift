import Foundation
import Testing
@testable import DualFinderCore

@Suite("ProcessCommandRunner")
struct ProcessCommandRunnerTests {
    @Test("captures stdout stderr and exit code")
    func capturesOutputAndExitCode() throws {
        let result = try ProcessCommandRunner().run(
            executable: "/bin/sh",
            arguments: ["-c", "printf out; printf err >&2; exit 7"],
            workingDirectory: nil
        )

        #expect(result.exitCode == 7)
        #expect(result.stdout == "out")
        #expect(result.stderr == "err")
        #expect(!result.succeeded)
    }

    @Test("runs in the requested working directory")
    func runsInRequestedWorkingDirectory() throws {
        let directory = try TemporaryDirectory()

        let result = try ProcessCommandRunner().run(
            executable: "/bin/pwd",
            arguments: [],
            workingDirectory: directory.url
        )

        #expect(result.succeeded)
        #expect(
            URL(fileURLWithPath: result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)).standardizedFileURL
                == directory.url.standardizedFileURL
        )
    }

    @Test("captures output while process is still running")
    func capturesOutputWhileProcessIsStillRunning() throws {
        let stdoutBytes = 1024 * 1024
        let stderrBytes = 256 * 1024

        let result = try ProcessCommandRunner().run(
            executable: "/usr/bin/perl",
            arguments: [
                "-e",
                "print 'o' x \(stdoutBytes); print STDERR 'e' x \(stderrBytes);"
            ],
            workingDirectory: nil
        )

        #expect(result.succeeded)
        #expect(result.stdout.count == stdoutBytes)
        #expect(result.stderr.count == stderrBytes)
    }

    @Test("caps captured output when maxCapturedOutputBytes is set")
    func capsCapturedOutputWhenMaxIsSet() throws {
        let stdoutBytes = 1024 * 1024
        let result = try ProcessCommandRunner(maxCapturedOutputBytes: 64 * 1024).run(
            executable: "/usr/bin/perl",
            arguments: [
                "-e",
                "print 'o' x \(stdoutBytes);"
            ],
            workingDirectory: nil
        )

        #expect(result.succeeded)
        #expect(result.stdout.count == 64 * 1024)
    }

    @Test("terminates running process when cancelled")
    func terminatesRunningProcessWhenCancelled() throws {
        let cancellation = FileOperationCancellation()
        Task { try? await Task.sleep(for: .milliseconds(200)); cancellation.cancel() }

        let startedAt = Date()
        #expect(throws: FileOperationError.cancelled) {
            _ = try ProcessCommandRunner().run(
                executable: "/bin/sleep",
                arguments: ["5"],
                workingDirectory: nil,
                cancellation: cancellation
            )
        }
        // sleep 5 would naturally complete at ~5s; cancellation must return
        // well before that. Tighten to 1.5s to verify cancel actually fires
        // (rather than the test passing because sleep finished). Allow slack
        // for parallel-test scheduling jitter on the global dispatch queue.
        #expect(Date().timeIntervalSince(startedAt) < 1.5)
    }
}
