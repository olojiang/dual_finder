import Foundation

public enum AndroidDeviceState: Sendable, Equatable {
    case device
    case unauthorized
    case offline
    case recovery
    case sideload
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "device":
            self = .device
        case "unauthorized":
            self = .unauthorized
        case "offline":
            self = .offline
        case "recovery":
            self = .recovery
        case "sideload":
            self = .sideload
        default:
            self = .unknown(rawValue)
        }
    }
}

public struct AndroidDevice: Identifiable, Sendable, Equatable {
    public var id: String { serial }
    public let serial: String
    public let state: AndroidDeviceState
    public let product: String?
    public let model: String?
    public let device: String?

    public init(
        serial: String,
        state: AndroidDeviceState,
        product: String? = nil,
        model: String? = nil,
        device: String? = nil
    ) {
        self.serial = serial
        self.state = state
        self.product = product
        self.model = model
        self.device = device
    }
}

public struct AndroidRemoteFile: Sendable, Equatable {
    public let path: String
    public let size: Int64

    public init(path: String, size: Int64) {
        self.path = path
        self.size = size
    }
}

public enum AndroidFileError: LocalizedError, Equatable {
    case commandFailed(arguments: [String], exitCode: Int32, detail: String)
    case invalidAndroidURL(URL)

    public var errorDescription: String? {
        switch self {
        case .commandFailed(let arguments, let exitCode, let detail):
            "ADB command failed (\(exitCode)): \(arguments.joined(separator: " ")). \(detail)"
        case .invalidAndroidURL(let url):
            "Invalid Android URL: \(url.absoluteString)"
        }
    }
}

public enum AndroidFileURL {
    public static let scheme = "android"

    public static func url(deviceSerial: String, path: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = "file"
        components.path = "/" + deviceSerial + normalizedPath(path)
        return components.url!
    }

    public static func parse(_ url: URL) -> (deviceSerial: String, path: String)? {
        guard url.scheme == scheme else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return nil }
        let serial = String(parts[1])
        guard !serial.isEmpty else { return nil }
        let remotePath: String
        if parts.count <= 2 {
            remotePath = "/"
        } else {
            remotePath = "/" + parts.dropFirst(2).joined(separator: "/")
        }
        return (serial, normalizedPath(remotePath))
    }

    public static func path(from url: URL) throws -> String {
        guard let parsed = parse(url) else { throw AndroidFileError.invalidAndroidURL(url) }
        return parsed.path
    }

    public static func normalizedPath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "/" }
        let withRoot = trimmed.hasPrefix("/") ? trimmed : "/" + trimmed
        var components: [String] = []
        for component in withRoot.split(separator: "/") {
            switch component {
            case ".", "":
                continue
            case "..":
                if !components.isEmpty {
                    components.removeLast()
                }
            default:
                components.append(String(component))
            }
        }
        return "/" + components.joined(separator: "/")
    }

    public static func appending(_ name: String, to path: String) -> String {
        let base = normalizedPath(path)
        return base == "/" ? "/\(name)" : "\(base)/\(name)"
    }

    public static func parent(of path: String) -> String? {
        let normalized = normalizedPath(path)
        guard normalized != "/" else { return nil }
        let parent = (normalized as NSString).deletingLastPathComponent
        return parent.isEmpty ? "/" : parent
    }
}

public struct AndroidFileService: Sendable {
    private let commandRunner: any CommandRunning
    private let adbExecutable: String
    private let adbArgumentPrefix: [String]
    private let logger: AppLogging?

    public init(
        adbExecutable: String = AndroidFileService.defaultADBExecutable(),
        commandRunner: any CommandRunning = ProcessCommandRunner(maxCapturedOutputBytes: 1_048_576),
        logger: AppLogging? = nil
    ) {
        self.adbExecutable = adbExecutable
        self.adbArgumentPrefix = adbExecutable == "/usr/bin/env" ? ["adb"] : []
        self.commandRunner = commandRunner
        self.logger = logger
    }

    public func devices() throws -> [AndroidDevice] {
        let result = try runADBChecked(["devices", "-l"])
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .dropFirst()
            .compactMap(parseDeviceLine)
    }

    public func contents(
        of remotePath: String,
        on deviceSerial: String,
        includeHidden: Bool = false
    ) throws -> [FileItem] {
        let path = AndroidFileURL.normalizedPath(remotePath)
        let command = "ls -la \(shellSingleQuoted(directoryListingPath(for: path)))"
        let result = try runDeviceShellChecked(command, on: deviceSerial)
        let lines = result.stdout.split(whereSeparator: \.isNewline)
        let items = lines
            .compactMap { parseLongListLine(String($0), parentPath: path, deviceSerial: deviceSerial) }
            .filter { includeHidden || !$0.name.hasPrefix(".") }
            .sorted(by: sortAndroidItems)
        if items.isEmpty && !lines.isEmpty {
            logger?.warning("android", "directory.parse.empty", metadata: [
                "device": deviceSerial,
                "path": path,
                "stdoutLines": "\(lines.count)",
                "firstLines": firstOutputLines(result.stdout)
            ])
        }
        return items
    }

    @discardableResult
    public func createDirectory(named name: String, in remoteDirectory: String, on deviceSerial: String) throws -> String {
        try validateRemoteName(name)
        let path = AndroidFileURL.appending(name, to: remoteDirectory)
        try runDeviceShellChecked("mkdir \(shellSingleQuoted(path))", on: deviceSerial)
        return path
    }

    @discardableResult
    public func createEmptyFile(named name: String, in remoteDirectory: String, on deviceSerial: String) throws -> String {
        try validateRemoteName(name)
        let path = AndroidFileURL.appending(name, to: remoteDirectory)
        try runDeviceShellChecked("touch \(shellSingleQuoted(path))", on: deviceSerial)
        return path
    }

    public func copyRemote(_ remotePaths: [String], to remoteDirectory: String, on deviceSerial: String) throws {
        guard !remotePaths.isEmpty else { return }
        let sources = remotePaths.map { shellSingleQuoted(AndroidFileURL.normalizedPath($0)) }.joined(separator: " ")
        try runDeviceShellChecked(
            "cp -R \(sources) \(shellSingleQuoted(AndroidFileURL.normalizedPath(remoteDirectory) + "/"))",
            on: deviceSerial
        )
    }

    public func moveRemote(_ remotePaths: [String], to remoteDirectory: String, on deviceSerial: String) throws {
        guard !remotePaths.isEmpty else { return }
        let sources = remotePaths.map { shellSingleQuoted(AndroidFileURL.normalizedPath($0)) }.joined(separator: " ")
        try runDeviceShellChecked(
            "mv \(sources) \(shellSingleQuoted(AndroidFileURL.normalizedPath(remoteDirectory) + "/"))",
            on: deviceSerial
        )
    }

    public func renameRemote(_ remotePath: String, to newName: String, on deviceSerial: String) throws -> String {
        try validateRemoteName(newName)
        let path = AndroidFileURL.normalizedPath(remotePath)
        let parent = AndroidFileURL.parent(of: path) ?? "/"
        let destination = AndroidFileURL.appending(newName, to: parent)
        try runDeviceShellChecked(
            "mv \(shellSingleQuoted(path)) \(shellSingleQuoted(destination))",
            on: deviceSerial
        )
        return destination
    }

    public func removeRemote(_ remotePaths: [String], on deviceSerial: String) throws {
        guard !remotePaths.isEmpty else { return }
        let paths = remotePaths.map { shellSingleQuoted(AndroidFileURL.normalizedPath($0)) }.joined(separator: " ")
        try runDeviceShellChecked("rm -rf \(paths)", on: deviceSerial)
    }

    public func push(
        localURLs: [URL],
        to remoteDirectory: String,
        on deviceSerial: String,
        sync: Bool = false,
        cancellation: FileOperationCancellation? = nil
    ) throws {
        for url in localURLs {
            _ = try runADBChecked([
                "-s", deviceSerial, "push"
            ] + (sync ? ["--sync"] : []) + [
                url.path,
                AndroidFileURL.normalizedPath(remoteDirectory) + "/"
            ], cancellation: cancellation)
        }
    }

    public func pull(
        remotePaths: [String],
        to localDirectory: URL,
        on deviceSerial: String,
        cancellation: FileOperationCancellation? = nil
    ) throws {
        for path in remotePaths {
            _ = try runADBChecked([
                "-s", deviceSerial, "pull", AndroidFileURL.normalizedPath(path),
                localDirectory.standardizedFileURL.path + "/"
            ], cancellation: cancellation)
        }
    }

    public func pullFile(
        remotePath: String,
        to localFile: URL,
        on deviceSerial: String,
        cancellation: FileOperationCancellation? = nil
    ) throws {
        try FileManager.default.createDirectory(
            at: localFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        _ = try runADBChecked([
            "-s", deviceSerial, "pull", AndroidFileURL.normalizedPath(remotePath),
            localFile.standardizedFileURL.path
        ], cancellation: cancellation)
    }

    public func estimatedByteSize(of remotePath: String, on deviceSerial: String) -> Int64? {
        let path = AndroidFileURL.normalizedPath(remotePath)
        let command = "du -sk \(shellSingleQuoted(path)) 2>/dev/null"
        guard let result = try? runDeviceShell(command, on: deviceSerial),
              result.succeeded,
              let firstField = result.stdout.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" }).first,
              let kilobytes = Int64(firstField) else {
            return nil
        }
        return max(kilobytes, 0) * 1024
    }

    public func regularFiles(
        under remotePath: String,
        on deviceSerial: String,
        cancellation: FileOperationCancellation? = nil
    ) throws -> [AndroidRemoteFile] {
        let path = AndroidFileURL.normalizedPath(remotePath)
        let quotedPath = shellSingleQuoted(path)
        let command = """
        if [ -f \(quotedPath) ]; then stat -c '%s %n' \(quotedPath); elif [ -d \(quotedPath) ]; then find \(quotedPath) -type f -exec stat -c '%s %n' {} + ; fi
        """
        let result = try runDeviceShellChecked(command, on: deviceSerial, cancellation: cancellation)
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap(parseRemoteFileStatLine)
            .sorted { $0.path < $1.path }
    }

    public func logSyncDecision(_ action: String, remotePath: String, localPath: String, size: Int64) {
        logger?.info("android-sync", action, metadata: [
            "remote": remotePath,
            "local": localPath,
            "size": "\(size)"
        ])
    }

    private func parseRemoteFileStatLine(_ line: Substring) -> AndroidRemoteFile? {
        let text = String(line)
        guard let separator = text.firstIndex(where: { $0 == " " || $0 == "\t" }) else { return nil }
        let sizeText = text[..<separator]
        let pathText = text[separator...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let size = Int64(sizeText), !pathText.isEmpty else { return nil }
        return AndroidRemoteFile(path: AndroidFileURL.normalizedPath(pathText), size: size)
    }

    private func parseDeviceLine(_ line: Substring) -> AndroidDevice? {
        let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count >= 2 else { return nil }
        let properties = fields.dropFirst(2).reduce(into: [String: String]()) { properties, field in
            let parts = field.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { return }
            properties[String(parts[0])] = String(parts[1])
        }
        return AndroidDevice(
            serial: String(fields[0]),
            state: AndroidDeviceState(rawValue: String(fields[1])),
            product: properties["product"],
            model: properties["model"],
            device: properties["device"]
        )
    }

    private func parseLongListLine(_ line: String, parentPath: String, deviceSerial: String) -> FileItem? {
        guard !line.hasPrefix("total ") else { return nil }

        let fields = line.split(maxSplits: 7, whereSeparator: { $0 == " " || $0 == "\t" })
        guard fields.count == 8 else { return nil }

        let permissions = String(fields[0])
        var name = String(fields[7])
        if permissions.hasPrefix("l"),
           let targetSeparator = name.range(of: " -> ") {
            name = String(name[..<targetSeparator.lowerBound])
        }
        guard name != "." && name != ".." else { return nil }

        let size = Int64(fields[4])
        let kind: FileItemKind
        switch permissions.first {
        case "d":
            kind = .folder
        case "-":
            kind = .file
        case "l":
            kind = .alias
        default:
            kind = .other
        }
        let path = AndroidFileURL.appending(name, to: parentPath)
        return FileItem(
            url: AndroidFileURL.url(deviceSerial: deviceSerial, path: path),
            name: name,
            kind: kind,
            type: androidTypeLabel(for: kind),
            size: kind == .file ? size : nil,
            modifiedAt: parseLongListModifiedAt(date: String(fields[5]), time: String(fields[6])),
            isHidden: name.hasPrefix(".")
        )
    }

    private func parseLongListModifiedAt(date: String, time: String) -> Date? {
        let dateParts = date.split(separator: "-").compactMap { Int($0) }
        let timeParts = time.split(separator: ":").compactMap { Int($0) }
        guard dateParts.count == 3, timeParts.count >= 2 else { return nil }

        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = dateParts[0]
        components.month = dateParts[1]
        components.day = dateParts[2]
        components.hour = timeParts[0]
        components.minute = timeParts[1]
        components.second = timeParts.count >= 3 ? timeParts[2] : 0
        return components.date
    }

    private func androidTypeLabel(for kind: FileItemKind) -> String {
        switch kind {
        case .folder:
            return "Android folder"
        case .file:
            return "Android file"
        case .alias:
            return "Android link"
        case .package:
            return "Android package"
        case .other:
            return "Android item"
        }
    }

    private func sortAndroidItems(_ left: FileItem, _ right: FileItem) -> Bool {
        if left.isDirectoryLike != right.isDirectoryLike {
            return left.isDirectoryLike
        }
        return left.name.localizedStandardCompare(right.name) == .orderedAscending
    }

    private func directoryListingPath(for path: String) -> String {
        path == "/" ? "/" : path + "/"
    }

    @discardableResult
    private func runDeviceShell(_ command: String, on deviceSerial: String) throws -> CommandResult {
        try runADB(["-s", deviceSerial, "shell", command])
    }

    @discardableResult
    private func runDeviceShellChecked(
        _ command: String,
        on deviceSerial: String,
        cancellation: FileOperationCancellation? = nil
    ) throws -> CommandResult {
        try runADBChecked(["-s", deviceSerial, "shell", command], cancellation: cancellation)
    }

    @discardableResult
    private func runADBChecked(
        _ arguments: [String],
        cancellation: FileOperationCancellation? = nil
    ) throws -> CommandResult {
        let result = try runADB(arguments, cancellation: cancellation)
        guard result.succeeded else {
            throw AndroidFileError.commandFailed(
                arguments: ["adb"] + arguments,
                exitCode: result.exitCode,
                detail: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result
    }

    private func runADB(
        _ arguments: [String],
        cancellation: FileOperationCancellation? = nil
    ) throws -> CommandResult {
        let processArguments = adbArgumentPrefix + arguments
        logger?.debug("android", "adb.started", metadata: [
            "executable": adbExecutable,
            "arguments": processArguments.joined(separator: " ")
        ])
        let result: CommandResult
        if let cancellableRunner = commandRunner as? CancellableCommandRunning {
            result = try cancellableRunner.run(
                executable: adbExecutable,
                arguments: processArguments,
                workingDirectory: nil,
                cancellation: cancellation
            )
        } else {
            result = try commandRunner.run(executable: adbExecutable, arguments: processArguments, workingDirectory: nil)
        }
        logger?.debug("android", "adb.completed", metadata: [
            "executable": adbExecutable,
            "arguments": processArguments.joined(separator: " "),
            "exitCode": "\(result.exitCode)",
            "stdoutLines": "\(result.stdout.split(whereSeparator: \.isNewline).count)",
            "stderr": firstOutputLines(result.stderr)
        ])
        return result
    }

    public static func defaultADBExecutable(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> String {
        let sdkRoots = [
            environment["ANDROID_HOME"],
            environment["ANDROID_SDK_ROOT"],
            homeDirectory.appendingPathComponent("Library/Android/sdk").path
        ].compactMap { $0 }

        let candidates = sdkRoots.map { root in
            URL(fileURLWithPath: root)
                .appendingPathComponent("platform-tools")
                .appendingPathComponent("adb")
                .path
        } + [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb"
        ]

        if let resolved = candidates.first(where: { fileManager.isExecutableFile(atPath: $0) }) {
            return resolved
        }

        return "/usr/bin/env"
    }

    private func validateRemoteName(_ name: String) throws {
        guard !FileNameUtilities.isBlank(name),
              !FileNameUtilities.containsInvalidPathComponentCharacters(name) else {
            throw FileOperationError.emptyName
        }
    }

    private func shellSingleQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private func firstOutputLines(_ output: String, limit: Int = 3) -> String {
        output
            .split(whereSeparator: \.isNewline)
            .prefix(limit)
            .joined(separator: " | ")
    }
}
