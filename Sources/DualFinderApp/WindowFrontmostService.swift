import AppKit
import DualFinderCore

@MainActor
final class WindowFrontmostService {
    private let logger: AppLogging

    init(logger: AppLogging = AppDelegate.sharedLogger) {
        self.logger = logger
    }

    func bringApplicationToFront() {
        logger.info("window-front", "bring.started", metadata: applicationDebugMetadata())

        NSApp.unhide(nil)
        activateApplicationWithAllWindows()

        let candidates = NSApp.windows.filter(isNormalContentWindow)
        logger.info("window-front", "bring.candidates", metadata: [
            "count": "\(candidates.count)",
            "windows": candidates.map(windowDebugLabel).joined(separator: " | ")
        ])

        for window in candidates where window.isMiniaturized {
            logger.info("window-front", "deminiaturize.queued", metadata: windowMetadata(window))
            window.deminiaturize(nil)
        }

        guard let window = resolveMainWindow(from: candidates) else {
            logger.warning("window-front", "bring.no-window", metadata: applicationDebugMetadata())
            NSApp.arrangeInFront(nil)
            return
        }

        if window.isMiniaturized {
            Task { @MainActor [weak self] in
                await self?.waitForDeminiaturize(window)
                self?.finishBringToFront(window)
            }
        } else {
            finishBringToFront(window)
        }
    }

    private func activateApplicationWithAllWindows() {
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func waitForDeminiaturize(_ window: NSWindow) async {
        logger.info("window-front", "deminiaturize.waiting", metadata: windowMetadata(window))
        for attempt in 1...8 where window.isMiniaturized {
            window.deminiaturize(nil)
            try? await Task.sleep(for: .milliseconds(attempt == 1 ? 30 : 60))
        }
        if window.isMiniaturized {
            logger.error("window-front", "deminiaturize.failed", metadata: windowMetadata(window))
        } else {
            logger.info("window-front", "deminiaturize.completed", metadata: windowMetadata(window))
        }
    }

    private func finishBringToFront(_ window: NSWindow) {
        var behavior = window.collectionBehavior
        behavior.insert(.moveToActiveSpace)
        window.collectionBehavior = behavior

        if let screen = screenForFrontmostWindow() {
            window.setFrame(screen.visibleFrame, display: true, animate: false)
        } else {
            window.zoom(nil)
        }

        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        activateApplicationWithAllWindows()

        logger.info("window-front", "bring.completed", metadata: windowMetadata(window))
    }

    private func resolveMainWindow(from candidates: [NSWindow]) -> NSWindow? {
        let snapshots = candidates.map(snapshot(for:))
        guard let selected = MainWindowSelector.select(from: snapshots) else { return nil }
        return candidates.first(where: { $0.windowNumber == selected.windowNumber })
    }

    private func isNormalContentWindow(_ window: NSWindow) -> Bool {
        !window.isSheet && window.level == .normal
    }

    private func snapshot(for window: NSWindow) -> WindowSelectionSnapshot {
        WindowSelectionSnapshot(
            windowNumber: window.windowNumber,
            title: window.title,
            isMiniaturized: window.isMiniaturized,
            isVisible: window.isVisible,
            canBecomeMain: window.canBecomeMain,
            isSheet: window.isSheet,
            level: Int(window.level.rawValue)
        )
    }

    private func screenForFrontmostWindow() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLocation, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    private func applicationDebugMetadata() -> [String: String] {
        [
            "isHidden": "\(NSApp.isHidden)",
            "isActive": "\(NSApp.isActive)",
            "windowCount": "\(NSApp.windows.count)",
            "mainWindow": NSApp.mainWindow.map(windowDebugLabel) ?? "nil",
            "keyWindow": NSApp.keyWindow.map(windowDebugLabel) ?? "nil"
        ]
    }

    private func windowMetadata(_ window: NSWindow) -> [String: String] {
        [
            "title": window.title,
            "windowNumber": "\(window.windowNumber)",
            "isMiniaturized": "\(window.isMiniaturized)",
            "isVisible": "\(window.isVisible)",
            "canBecomeMain": "\(window.canBecomeMain)",
            "level": "\(window.level.rawValue)"
        ]
    }

    private func windowDebugLabel(_ window: NSWindow) -> String {
        "\(window.title)#\(window.windowNumber)(mini=\(window.isMiniaturized),vis=\(window.isVisible),main=\(window.canBecomeMain))"
    }
}
