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
}
