import AppKit
import Carbon.HIToolbox
import DualFinderCore
import Foundation

private let helperLogger = AppLogger()

final class HotkeyHelperApp: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var hotkeyPollTimer: Timer?
    private var registeredBinding: ShowWindowHotkeyBinding?
    private let store = ShowWindowHotkeyStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        helperLogger.info("hotkey-helper", "helper.launched", metadata: [
            "logDirectory": helperLogger.logDirectory.path
        ])
        if !installHotKey(preservingExisting: false) {
            helperLogger.error("hotkey-helper", "hotkey.register.failed", metadata: [:])
            fputs("DualFinderHotkeyHelper: failed to register global hotkey\n", stderr)
            NSApp.terminate(nil)
            return
        }
        helperLogger.info("hotkey-helper", "hotkey.registered", metadata: [
            "binding": store.binding().displayLabel
        ])
        observeHotkeyChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeyPollTimer?.invalidate()
        hotkeyPollTimer = nil
        removeHotKey()
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: ShowWindowHotkeyStore.distributedDidChangeNotification,
            object: nil
        )
    }

    private func installHotKey(preservingExisting: Bool) -> Bool {
        let binding = store.binding()
        let previousBinding = registeredBinding
        removeHotKey(clearRegisteredBinding: !preservingExisting)

        if installHotKey(binding: binding) {
            return true
        }

        if preservingExisting, let previousBinding {
            _ = installHotKey(binding: previousBinding)
        }
        return false
    }

    private func installHotKey(binding: ShowWindowHotkeyBinding) -> Bool {
        let nextHotKeyID = UInt32.random(in: 1...UInt32.max)
        var nextHotKeyRef: EventHotKeyRef?
        var nextHandlerRef: EventHandlerRef?
        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard GetEventKind(event) == UInt32(kEventHotKeyPressed) else {
                    return OSStatus(eventNotHandledErr)
                }
                HotkeyHelperApp.handleHotKey()
                return noErr
            },
            1,
            &eventType,
            nil,
            &nextHandlerRef
        )
        guard status == noErr else { return false }

        let hotKeyID = EventHotKeyID(signature: HotkeyHelperApp.signature, id: nextHotKeyID)
        let registerStatus = RegisterEventHotKey(
            UInt32(binding.keyCode),
            Self.carbonModifiers(for: binding),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &nextHotKeyRef
        )
        guard registerStatus == noErr else {
            if let nextHandlerRef {
                RemoveEventHandler(nextHandlerRef)
            }
            return false
        }

        hotKeyRef = nextHotKeyRef
        handlerRef = nextHandlerRef
        registeredBinding = binding
        return true
    }

    private func removeHotKey(clearRegisteredBinding: Bool = true) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
        if clearRegisteredBinding {
            registeredBinding = nil
        }
    }

    private func observeHotkeyChanges() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleHotkeyConfigurationChanged(_:)),
            name: ShowWindowHotkeyStore.distributedDidChangeNotification,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        hotkeyPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.reloadHotKeyIfBindingChanged(source: "poll")
        }
    }

    @objc
    private func handleHotkeyConfigurationChanged(_ notification: Notification) {
        reloadHotKeyIfBindingChanged(source: "notification")
    }

    private func reloadHotKeyIfBindingChanged(source: String) {
        let nextBinding = store.binding()
        guard nextBinding != registeredBinding else { return }

        if installHotKey(preservingExisting: true) {
            helperLogger.info("hotkey-helper", "hotkey.reloaded", metadata: [
                "binding": nextBinding.displayLabel,
                "source": source
            ])
        } else {
            helperLogger.error("hotkey-helper", "hotkey.reload.failed", metadata: [
                "binding": nextBinding.displayLabel,
                "source": source
            ])
        }
    }

    private static func carbonModifiers(for binding: ShowWindowHotkeyBinding) -> UInt32 {
        var modifiers: UInt32 = 0
        if binding.modifiers.contains(.command) { modifiers |= UInt32(cmdKey) }
        if binding.modifiers.contains(.option) { modifiers |= UInt32(optionKey) }
        if binding.modifiers.contains(.control) { modifiers |= UInt32(controlKey) }
        if binding.modifiers.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func handleHotKey() {
        helperLogger.info("hotkey-helper", "hotkey.pressed", metadata: [:])
        if InstanceActivationSignaling.sendShowWindowRequest() {
            helperLogger.info("hotkey-helper", "socket.delivered", metadata: [:])
            return
        }
        helperLogger.info("hotkey-helper", "socket.missed-launching-app", metadata: [:])
        launchMainApplication()
    }

    private static func launchMainApplication() {
        if let bundleURL = mainApplicationBundleURL() {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration)
            return
        }

        if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: InstanceActivationSignaling.bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            configuration.createsNewApplicationInstance = false
            NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        }
    }

    private static func mainApplicationBundleURL() -> URL? {
        let helperBundle = Bundle.main.bundleURL
        let loginItemCandidate = helperBundle
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        if loginItemCandidate.pathExtension == "app",
           FileManager.default.fileExists(atPath: loginItemCandidate.path) {
            return loginItemCandidate
        }

        let applications = "/Applications"
        let names = ["Dual Finder 纪.app", "DualFinder.app"]
        for name in names {
            let url = URL(fileURLWithPath: applications).appendingPathComponent(name, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        return nil
    }

    private static let signature: OSType = {
        var value: UInt32 = 0
        for byte in [UInt8(ascii: "D"), UInt8(ascii: "F"), UInt8(ascii: "N"), UInt8(ascii: "D")] {
            value = (value << 8) + UInt32(byte)
        }
        return OSType(value)
    }()
}

let app = NSApplication.shared
let delegate = HotkeyHelperApp()
app.delegate = delegate
app.run()
