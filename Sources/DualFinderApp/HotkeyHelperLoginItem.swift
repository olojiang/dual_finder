import AppKit
import Foundation
import ServiceManagement

enum HotkeyHelperLoginItem {
    static let helperBundleIdentifier = "com.local.dualfinder.hotkey-helper"
    static let registrationAttemptedKey = "hotkeyHelperLoginItem.registrationAttempted"

    static var loginItem: SMAppService? {
        SMAppService.loginItem(identifier: helperBundleIdentifier)
    }

    static var isRegistered: Bool {
        loginItem?.status == .enabled
    }

    @discardableResult
    static func register() -> Bool {
        guard let loginItem else { return false }
        do {
            try loginItem.register()
            return loginItem.status == .enabled
        } catch {
            return false
        }
    }

    static func unregister() {
        try? loginItem?.unregister()
    }

    static func restartRunningHelperFromEmbeddedApp() {
        for runningApplication in NSRunningApplication.runningApplications(withBundleIdentifier: helperBundleIdentifier) {
            runningApplication.terminate()
        }

        guard let helperURL = embeddedHelperURL() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: helperURL, configuration: configuration)
        }
    }

    static func openLoginItemsSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.LoginItems-Settings.extension",
            "x-apple.systempreferences:com.apple.settings.LoginItems"
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) {
                return
            }
        }
    }

    static func embeddedHelperURL(in appBundle: Bundle = .main) -> URL? {
        let url = appBundle.bundleURL
            .appendingPathComponent("Contents/Library/LoginItems/DualFinderHotkeyHelper.app", isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
