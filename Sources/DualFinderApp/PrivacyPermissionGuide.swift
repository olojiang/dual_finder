import AppKit
import DualFinderCore
import Foundation

struct PrivacyPermissionGuide {
    private static let fullDiskAccessURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
    )
    private static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy"
    )

    /// The global show-window shortcut uses Carbon hotkeys and does not require Accessibility.
    /// The optional login-item helper only needs approval under Login Items.
    static var showWindowHotkeyNotes: String {
        """
        Dual Finder registers \(ShowWindowHotkeyStore().binding().displayLabel) with the system hotkey API (Carbon), not Accessibility, so rebuilding \
        with the same bundle id and codesign identity should not reset Accessibility permissions.
        When the login-item helper is enabled, macOS may ask once under Settings → General → Login Items.
        """
    }

    func openFullDiskAccessSettings() {
        if let fullDiskAccessURL = Self.fullDiskAccessURL, NSWorkspace.shared.open(fullDiskAccessURL) {
            return
        }
        if let privacySettingsURL = Self.privacySettingsURL {
            NSWorkspace.shared.open(privacySettingsURL)
        }
    }

    func fullDiskAccessProbeFailure() -> Error? {
        let probeURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("com.apple.TCC")
            .appendingPathComponent("TCC.db")

        do {
            let handle = try FileHandle(forReadingFrom: probeURL)
            try? handle.close()
            return nil
        } catch {
            return isFilePermissionDenied(error) ? error : nil
        }
    }

    func isFilePermissionDenied(_ error: Error) -> Bool {
        let nsError = error as NSError
        if isPermissionDenied(nsError) {
            return true
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isPermissionDenied(underlying)
        }
        return false
    }

    private func isPermissionDenied(_ error: NSError) -> Bool {
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileReadNoPermissionError,
                NSFileWriteNoPermissionError:
                return true
            default:
                break
            }
        }

        if error.domain == NSPOSIXErrorDomain {
            return error.code == Int(EACCES) || error.code == Int(EPERM)
        }

        return false
    }
}

struct DiskAccessPrompt: Identifiable {
    let id = UUID()
    let path: String
    let message: String
}

struct ShowWindowHotkeyPrompt: Identifiable {
    let id = UUID()
    let message: String
}
