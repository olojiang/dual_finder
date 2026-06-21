import Foundation
import Testing
@testable import DualFinderCore

@Suite("AndroidFileService")
struct AndroidFileServiceTests {
    @Test("resolves adb from the Android SDK under home")
    func resolvesADBFromAndroidSDKUnderHome() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DualFinderAndroidSDK-\(UUID().uuidString)")
        let adb = root
            .appendingPathComponent("Library/Android/sdk/platform-tools/adb")
        try FileManager.default.createDirectory(
            at: adb.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: adb.path, contents: Data())
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: adb.path)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AndroidFileService.defaultADBExecutable(environment: [:], homeDirectory: root) == adb.path)
    }

    @Test("parses connected android devices from adb output")
    func parsesConnectedAndroidDevices() throws {
        let runner = RecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                List of devices attached
                emulator-5554 device product:sdk_gphone64_arm64 model:old model:sdk_gphone64_arm64 device:emu64a transport_id:1
                R58N123ABC unauthorized usb:338690048X product:o1sxxx model:SM_G991B device:o1s
                
                """,
                stderr: ""
            )
        ])

        let devices = try AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner).devices()

        #expect(devices.map(\.serial) == ["emulator-5554", "R58N123ABC"])
        #expect(devices[0].state == .device)
        #expect(devices[0].model == "sdk_gphone64_arm64")
        #expect(devices[1].state == .unauthorized)
        #expect(runner.calls.first?.arguments == ["adb", "devices", "-l"])
    }

    @Test("lists remote android directory entries as file items")
    func listsRemoteDirectoryEntries() throws {
        let runner = RecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                total 12
                drwxrwx--x 2 root sdcard_rw 4096 2026-06-18 10:00 .
                drwxrwx--x 4 root sdcard_rw 4096 2026-06-18 09:00 ..
                drwxrwx--x 3 root sdcard_rw 4096 2026-06-18 10:01 Download
                -rw-rw---- 1 root sdcard_rw 128 2026-06-18 10:02 photo.jpg
                -rw-rw---- 1 root sdcard_rw 1 2026-06-18 10:03 .hidden
                lrwxrwxrwx 1 root sdcard_rw 11 2026-06-18 10:04 link -> /sdcard/foo
                
                """,
                stderr: ""
            )
        ])

        let items = try AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner).contents(
            of: "/sdcard",
            on: "emulator-5554",
            includeHidden: false
        )

        #expect(items.map(\.name) == ["Download", "link", "photo.jpg"])
        #expect(items[0].kind == .folder)
        #expect(items[0].url == AndroidFileURL.url(deviceSerial: "emulator-5554", path: "/sdcard/Download"))
        #expect(items[1].kind == .alias)
        #expect(items[2].kind == .file)
        #expect(items[2].size == 128)
        let modifiedComponents = Calendar(identifier: .gregorian).dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: try #require(items[2].modifiedAt)
        )
        #expect(modifiedComponents.year == 2026)
        #expect(modifiedComponents.month == 6)
        #expect(modifiedComponents.day == 18)
        #expect(modifiedComponents.hour == 10)
        #expect(modifiedComponents.minute == 2)
        #expect(runner.calls.first?.arguments == [
            "adb", "-s", "emulator-5554", "shell",
            "ls -la '/sdcard/'"
        ])
    }

    @Test("lists android symlinked storage roots by trailing slash")
    func listsSymlinkedStorageRootsByTrailingSlash() throws {
        let runner = RecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                total 8
                drwxrws--- 2 root media_rw 4096 2026-06-18 10:01 Download
                drwxrws--- 2 root media_rw 4096 2026-06-18 10:02 DCIM

                """,
                stderr: ""
            )
        ])

        let items = try AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner).contents(
            of: "/sdcard",
            on: "device-1"
        )

        #expect(items.map(\.name) == ["DCIM", "Download"])
        #expect(runner.calls.first?.arguments == [
            "adb", "-s", "device-1", "shell",
            "ls -la '/sdcard/'"
        ])
    }

    @Test("runs adb commands for remote and local file operations")
    func runsADBFileOperationCommands() throws {
        let runner = RecordingCommandRunner(results: Array(repeating: CommandResult(exitCode: 0, stdout: "", stderr: ""), count: 8))
        let service = AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner)
        let local = URL(fileURLWithPath: "/tmp/local file.txt")

        try service.createDirectory(named: "New Folder", in: "/sdcard", on: "device-1")
        try service.createEmptyFile(named: "note.txt", in: "/sdcard", on: "device-1")
        try service.copyRemote(["/sdcard/a.txt"], to: "/sdcard/Backup", on: "device-1")
        try service.moveRemote(["/sdcard/b.txt"], to: "/sdcard/Backup", on: "device-1")
        try service.removeRemote(["/sdcard/old.txt"], on: "device-1")
        try service.push(localURLs: [local], to: "/sdcard", on: "device-1")
        try service.pull(remotePaths: ["/sdcard/photo.jpg"], to: URL(fileURLWithPath: "/tmp"), on: "device-1")

        #expect(runner.calls.map(\.arguments) == [
            ["adb", "-s", "device-1", "shell", "mkdir '/sdcard/New Folder'"],
            ["adb", "-s", "device-1", "shell", "touch '/sdcard/note.txt'"],
            ["adb", "-s", "device-1", "shell", "cp -R '/sdcard/a.txt' '/sdcard/Backup/'"],
            ["adb", "-s", "device-1", "shell", "mv '/sdcard/b.txt' '/sdcard/Backup/'"],
            ["adb", "-s", "device-1", "shell", "rm -rf '/sdcard/old.txt'"],
            ["adb", "-s", "device-1", "push", "/tmp/local file.txt", "/sdcard/"],
            ["adb", "-s", "device-1", "pull", "/sdcard/photo.jpg", "/tmp/"]
        ])
    }

    @Test("throws command failure when adb returns nonzero")
    func throwsCommandFailureWhenADBReturnsNonzero() {
        let runner = RecordingCommandRunner(results: [
            CommandResult(exitCode: 1, stdout: "", stderr: "device unauthorized")
        ])

        #expect(throws: AndroidFileError.self) {
            _ = try AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner).devices()
        }
    }

    @Test("estimates remote byte size with du")
    func estimatesRemoteByteSizeWithDU() {
        let runner = RecordingCommandRunner(results: [
            CommandResult(exitCode: 0, stdout: "12\t/sdcard/DCIM\n", stderr: "")
        ])
        let service = AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner)

        #expect(service.estimatedByteSize(of: "/sdcard/DCIM", on: "device-1") == Int64(12 * 1024))
        #expect(runner.calls.first?.arguments == [
            "adb", "-s", "device-1", "shell", "du -sk '/sdcard/DCIM' 2>/dev/null"
        ])
    }

    @Test("lists regular files under remote path for sync decisions")
    func listsRegularFilesForSyncDecisions() throws {
        let runner = RecordingCommandRunner(results: [
            CommandResult(
                exitCode: 0,
                stdout: """
                10 /sdcard/Download/Book/a.txt
                20 /sdcard/Download/Book/Sub/b.txt

                """,
                stderr: ""
            )
        ])
        let service = AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner)

        let files = try service.regularFiles(under: "/sdcard/Download/Book", on: "device-1")

        #expect(files == [
            AndroidRemoteFile(path: "/sdcard/Download/Book/Sub/b.txt", size: 20),
            AndroidRemoteFile(path: "/sdcard/Download/Book/a.txt", size: 10)
        ])
        #expect(runner.calls.first?.arguments == [
            "adb", "-s", "device-1", "shell",
            "if [ -f '/sdcard/Download/Book' ]; then stat -c '%s %n' '/sdcard/Download/Book'; elif [ -d '/sdcard/Download/Book' ]; then find '/sdcard/Download/Book' -type f -exec stat -c '%s %n' {} + ; fi"
        ])
    }

    @Test("rejects blank or path-like remote names")
    func rejectsInvalidRemoteNames() {
        let runner = RecordingCommandRunner(results: [])
        let service = AndroidFileService(adbExecutable: "/usr/bin/env", commandRunner: runner)

        #expect(throws: FileOperationError.self) {
            _ = try service.createDirectory(named: " ", in: "/sdcard", on: "device-1")
        }
        #expect(throws: FileOperationError.self) {
            _ = try service.renameRemote("/sdcard/file.txt", to: "../file.txt", on: "device-1")
        }
    }
}

private final class RecordingCommandRunner: CommandRunning, @unchecked Sendable {
    struct Call: Equatable {
        let executable: String
        let arguments: [String]
        let workingDirectory: URL?
    }

    private let lock = NSLock()
    private var results: [CommandResult]
    private(set) var calls: [Call] = []

    init(results: [CommandResult]) {
        self.results = results
    }

    func run(
        executable: String,
        arguments: [String],
        workingDirectory: URL?
    ) throws -> CommandResult {
        lock.lock()
        defer { lock.unlock() }
        calls.append(Call(executable: executable, arguments: arguments, workingDirectory: workingDirectory))
        guard !results.isEmpty else {
            return CommandResult(exitCode: 0, stdout: "", stderr: "")
        }
        return results.removeFirst()
    }
}
