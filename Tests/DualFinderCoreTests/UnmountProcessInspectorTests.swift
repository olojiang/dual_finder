import Foundation
import Testing
@testable import DualFinderCore

@Suite("UnmountProcessInspector")
struct UnmountProcessInspectorTests {
    @Test("inspects the mounted filesystem with lsof and returns process paths")
    func inspectsMountedFilesystem() throws {
        let runner = RecordingUnmountCommandRunner(results: [
            CommandResult(
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
            ),
            CommandResult(
                exitCode: 0,
                stdout: """
                  412 hunter /System/Library/Frameworks/QuickLook.framework/Versions/A/Support/QuickLookUIService
                  812 hunter /System/Library/CoreServices/Finder.app/Contents/MacOS/Finder
                """,
                stderr: ""
            )
        ])
        let inspector = UnmountProcessInspector(commandRunner: runner)

        let blockers = try inspector.inspect(mountPoint: URL(fileURLWithPath: "/Volumes/Media"))

        #expect(runner.calls[0].executable == "/usr/sbin/lsof")
        #expect(runner.calls[0].arguments == ["-nP", "-Fpcn", "+f", "--", "/Volumes/Media"])
        #expect(runner.calls.map(\.executable) == ["/usr/sbin/lsof", "/bin/ps"])
        #expect(blockers == [
            UnmountProcessBlocker(
                processID: 812,
                processName: "Finder",
                openPaths: ["/Volumes/Media/Film One.mkv", "/Volumes/Media/Other.txt"],
                executablePath: "/System/Library/CoreServices/Finder.app/Contents/MacOS/Finder",
                userName: "hunter"
            ),
            UnmountProcessBlocker(
                processID: 412,
                processName: "QuickLookUIService",
                openPaths: ["/Volumes/Media/Film One.mkv"],
                executablePath: "/System/Library/Frameworks/QuickLook.framework/Versions/A/Support/QuickLookUIService",
                userName: "hunter"
            )
        ])
    }

    @Test("returns no blockers when lsof reports no open files")
    func returnsNoBlockersWhenNoFilesAreOpen() throws {
        let inspector = UnmountProcessInspector(commandRunner: RecordingUnmountCommandRunner(results: [.init(
            exitCode: 1,
            stdout: "",
            stderr: ""
        )]))

        #expect(try inspector.inspect(mountPoint: URL(fileURLWithPath: "/Volumes/Media")).isEmpty)
    }

    @Test("surfaces lsof diagnostics instead of claiming no blockers")
    func surfacesInspectionFailure() {
        let inspector = UnmountProcessInspector(commandRunner: RecordingUnmountCommandRunner(results: [.init(
            exitCode: 1,
            stdout: "",
            stderr: "lsof: permission denied"
        )]))

        #expect(throws: UnmountProcessInspectorError.commandFailed("lsof: permission denied")) {
            try inspector.inspect(mountPoint: URL(fileURLWithPath: "/Volumes/Media"))
        }
    }
}

private final class RecordingUnmountCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call {
        let executable: String
        let arguments: [String]
    }

    private var results: [CommandResult]
    private(set) var calls: [Call] = []
    private(set) var executable = ""
    private(set) var arguments: [String] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(executable: String, arguments: [String], workingDirectory: URL?) throws -> CommandResult {
        self.executable = executable
        self.arguments = arguments
        calls.append(Call(executable: executable, arguments: arguments))
        return results.removeFirst()
    }
}
