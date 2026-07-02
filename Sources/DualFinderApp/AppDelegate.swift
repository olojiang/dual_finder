import AppKit
import DualFinderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let sharedLogger = AppLogger()
    private var guardLock: SingleInstanceGuard?
    private var activationListener: InstanceActivationListener?
    private lazy var windowFrontmost = WindowFrontmostService(logger: Self.sharedLogger)
    private var globalHotkey: GlobalShowWindowHotkey?
    private var showWindowHotkeyObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let instanceGuard = SingleInstanceGuard(identifier: InstanceActivationSignaling.bundleIdentifier)
        guard instanceGuard.acquire() else {
            let delivered = InstanceActivationSignaling.sendShowWindowRequest()
            Self.sharedLogger.info("app.lifecycle", "single-instance.handoff", metadata: [
                "delivered": "\(delivered)"
            ])
            NSApp.terminate(nil)
            return
        }
        guardLock = instanceGuard
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        FrontendLogCapture.install(logger: Self.sharedLogger)
        Self.sharedLogger.info("app.lifecycle", "app.launched", metadata: [
            "logDirectory": Self.sharedLogger.logDirectory.path,
            "hotkeyHelperEnabled": "\(HotkeyHelperLoginItem.isRegistered)"
        ])

        startActivationListener()
        registerHotkeyHelperIfNeeded()
        restartRegisteredHotkeyHelperIfNeeded()
        observeShowWindowHotkeyChanges()
        installInProcessHotkeyIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.windowFrontmost.bringApplicationToFront()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.sharedLogger.info("app.lifecycle", "app.terminating")
        if let showWindowHotkeyObserver {
            NotificationCenter.default.removeObserver(showWindowHotkeyObserver)
            self.showWindowHotkeyObserver = nil
        }
        globalHotkey?.remove()
        globalHotkey = nil
        activationListener?.stop()
        activationListener = nil
        guardLock?.release()
    }

    func showMainWindowFromExternalRequest() {
        Self.sharedLogger.info("app.lifecycle", "show-window.requested", metadata: [:])
        windowFrontmost.bringApplicationToFront()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.sharedLogger.info("app.lifecycle", "dock.reopen", metadata: [
            "hasVisibleWindows": "\(flag)"
        ])
        showMainWindowFromExternalRequest()
        return true
    }

    private func startActivationListener() {
        let listener = InstanceActivationListener { [weak self] in
            Task { @MainActor in
                Self.sharedLogger.info("app.lifecycle", "activation.socket.received", metadata: [:])
                self?.showMainWindowFromExternalRequest()
            }
        }
        guard listener.start() else {
            Self.sharedLogger.warning("app.lifecycle", "activation.listener.failed", metadata: [:])
            return
        }
        activationListener = listener
    }

    private func registerHotkeyHelperIfNeeded() {
        guard !HotkeyHelperLoginItem.isRegistered else { return }
        guard HotkeyHelperLoginItem.embeddedHelperURL() != nil else {
            Self.sharedLogger.warning("app.lifecycle", "hotkey-helper.missing", metadata: [:])
            return
        }

        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: HotkeyHelperLoginItem.registrationAttemptedKey) else { return }

        defaults.set(true, forKey: HotkeyHelperLoginItem.registrationAttemptedKey)
        let registered = HotkeyHelperLoginItem.register()
        Self.sharedLogger.info("app.lifecycle", "hotkey-helper.register", metadata: [
            "registered": "\(registered)"
        ])
        if registered {
            globalHotkey?.remove()
            globalHotkey = nil
        }
    }

    private func restartRegisteredHotkeyHelperIfNeeded() {
        guard HotkeyHelperLoginItem.isRegistered else { return }
        guard HotkeyHelperLoginItem.embeddedHelperURL() != nil else {
            Self.sharedLogger.warning("app.lifecycle", "hotkey-helper.missing", metadata: [:])
            return
        }

        Self.sharedLogger.info("app.lifecycle", "hotkey-helper.restart", metadata: [:])
        HotkeyHelperLoginItem.restartRunningHelperFromEmbeddedApp()
    }

    private func installInProcessHotkeyIfNeeded() {
        guard !HotkeyHelperLoginItem.isRegistered else { return }

        let hotkey = makeInProcessHotkey()
        guard hotkey.install() else {
            Self.sharedLogger.warning("app.lifecycle", "hotkey.install.failed", metadata: [
                "binding": ShowWindowHotkeyStore().binding().displayLabel
            ])
            return
        }
        globalHotkey = hotkey
    }

    private func makeInProcessHotkey() -> GlobalShowWindowHotkey {
        let hotkey = GlobalShowWindowHotkey { [weak self] in
            Task { @MainActor in
                Self.sharedLogger.info("app.lifecycle", "hotkey.show-window", metadata: [:])
                self?.showMainWindowFromExternalRequest()
            }
        }
        return hotkey
    }

    private func observeShowWindowHotkeyChanges() {
        showWindowHotkeyObserver = NotificationCenter.default.addObserver(
            forName: ShowWindowHotkeyStore.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                Self.sharedLogger.info("app.lifecycle", "hotkey.binding.changed", metadata: [
                    "binding": ShowWindowHotkeyStore().binding().displayLabel
                ])
                self?.reloadInProcessHotkeyIfNeeded()
            }
        }
    }

    private func reloadInProcessHotkeyIfNeeded() {
        guard !HotkeyHelperLoginItem.isRegistered else { return }
        let replacement = makeInProcessHotkey()
        guard replacement.install() else {
            Self.sharedLogger.warning("app.lifecycle", "hotkey.reload.failed-keeping-previous", metadata: [
                "binding": ShowWindowHotkeyStore().binding().displayLabel
            ])
            return
        }
        globalHotkey?.remove()
        globalHotkey = replacement
    }
}
