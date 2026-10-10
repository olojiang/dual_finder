import Foundation
import Testing
@testable import DualFinderCore

@Suite("UnmountProcessInspector")
struct UnmountProcessInspectorTests {
    @Test("inspects the mounted filesystem with lsof and returns process paths")
    func inspectsMountedFilesystem() throws {
        let runner = RecordingUnmountCommandRunner(result: CommandResult(
            exitCode: 0,
            stdout: """
            p412
            cQuickLookUIService
            n/Volumes/Media/Film One.mkv
            p812
            cFinder
            n/Volumes/Media/Film One.mkv
            n/Volumes/Media/Other.txt
            """,
            stderr: ""
        ))
        let inspector = UnmountProcessInspector(commandRunner: runner)

        let blockers = try inspector.inspect(mountPoint: URL(fileURLWithPath: "/Volumes/Media"))

        #expect(runner.executable == "/usr/sbin/lsof")
        #expect(runner.arguments == ["-nP", "-Fpcn", "+f", "--", "/Volumes/Media"])
        #expect(blockers == [
            UnmountProcessBlocker(processID: 812, processName: "Finder", openPaths: ["/Volumes/Media/Film One.mkv", "/Volumes/Media/Other.txt"]),
            UnmountProcessBlocker(processID: 412, processName: "QuickLookUIService", openPaths: ["/Volumes/Media/Film One.mkv"])
        ])
    }

    @Test("returns no blockers when lsof reports no open files")
    func returnsNoBlockersWhenNoFilesAreOpen() throws {
        let inspector = UnmountProcessInspector(commandRunner: RecordingUnmountCommandRunner(result: .init(
            exitCode: 1,
            stdout: "",
            stderr: ""
        )))

        #expect(try inspector.inspect(mountPoint: URL(fileURLWithPath: "/Volumes/Media")).isEmpty)
    }

    @Test("surfaces lsof diagnostics instead of claiming no blockers")
    func surfacesInspectionFailure() {
        let inspector = UnmountProcessInspector(commandRunner: RecordingUnmountCommandRunner(result: .init(
            exitCode: 1,
            stdout: "",
            stderr: "lsof: permission denied"
        )))

        #expect(throws: UnmountProcessInspectorError.commandFailed("lsof: permission denied")) {
            try inspector.inspect(mountPoint: URL(fileURLWithPath: "/Volumes/Media"))
        }
    }
}

private final class RecordingUnmountCommandRunner: CommandRunning, @unchecked Sendable {
    let result: CommandResult
    private(set) var executable = ""
    private(set) var arguments: [String] = []

    init(result: CommandResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
        self.executable = executable
        self.arguments = arguments
        return result
    }
}
