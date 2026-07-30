import AppKit
import Foundation
import DualFinderCore

enum TerminalLauncher {
    static func openTerminal(at directory: URL, logger: AppLogging?) -> Bool {
        if NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.mitchellh.ghostty") != nil,
           openGhosttyTab(at: directory, logger: logger) {
            return true
        }

        return runOpen(arguments: ["-a", "Terminal", directory.path], logger: logger)
    }

    static func openInFinder(_ url: URL, logger: AppLogging?) {
        logger?.info("navigation", "file.opened.externally", metadata: ["path": url.path])
        NSWorkspace.shared.open(url)
    }

    static func openGhosttyTab(at directory: URL, logger: AppLogging?) -> Bool {
        let workingDirectory = ViewModelFormatters.appleScriptStringLiteral(directory.path)
        let script = """
        tell application "Ghostty"
            set surfaceConfig to new surface configuration from {initial working directory:\(workingDirectory)}
            if (count of windows) is greater than 0 then
                set newTab to new tab in front window with configuration surfaceConfig
                select tab newTab
            else
                new window with configuration surfaceConfig
            end if
            activate
        end tell
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return true
            }

            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            logger?.error("terminal", "ghostty.applescript.failed", metadata: [
                "path": directory.path,
                "error": errorMessage
            ])
            return false
        } catch {
            logger?.error("terminal", "ghostty.applescript.failed", metadata: [
                "path": directory.path,
                "error": error.localizedDescription
            ])
            return false
        }
    }

    static func runOpen(arguments: [String], logger: AppLogging?) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = arguments

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            logger?.error("terminal", "open.command.failed", metadata: [
                "arguments": arguments.joined(separator: " "),
                "error": error.localizedDescription
            ])
            return false
        }
    }
}
