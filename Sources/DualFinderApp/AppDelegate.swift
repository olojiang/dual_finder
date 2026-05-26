import AppKit
import DualFinderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let sharedLogger = AppLogger()
    private var guardLock: SingleInstanceGuard?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let instanceGuard = SingleInstanceGuard(identifier: "com.local.dualfinder")
        guard instanceGuard.acquire() else {
            Self.sharedLogger.warning("app.lifecycle", "single-instance.blocked", metadata: [
                "reason": "another instance owns lock"
            ])
            NSApp.terminate(nil)
            return
        }
        guardLock = instanceGuard
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Self.sharedLogger.info("app.lifecycle", "app.launched", metadata: [
            "logDirectory": Self.sharedLogger.logDirectory.path
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.maximizeMainWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedLogger.info("app.lifecycle", "app.terminating")
        guardLock?.release()
    }

    private func maximizeMainWindow() {
        guard let window = NSApp.windows.first(where: { $0.isVisible }) else { return }
        if let screen = window.screen ?? NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true, animate: false)
        } else {
            window.zoom(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
