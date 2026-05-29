import AppKit
import Quartz

enum PreviewNavigationDirection {
    case previous
    case next
}

@MainActor
final class QuickLookPreviewService: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var previewURLs: [URL] = []
    private var keyDownMonitor: Any?

    var navigationHandler: ((PreviewNavigationDirection) -> Bool)?
    var isPreviewVisible: Bool {
        QLPreviewPanel.shared()?.isVisible == true
    }

    func togglePreview(for urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible, previewURLs == urls {
            closePreview()
            return
        }

        showPreview(for: urls)
    }

    func showPreview(for urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        previewURLs = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        installKeyDownMonitor()
        panel.makeKeyAndOrderFront(nil)
    }

    func closePreview() {
        guard let panel = QLPreviewPanel.shared(), panel.isVisible else { return }
        panel.orderOut(nil)
        previewURLs = []
        panel.dataSource = nil
        panel.delegate = nil
        removeKeyDownMonitor()
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        previewURLs[index] as NSURL
    }

    func previewPanelDidClose(_ panel: QLPreviewPanel!) {
        previewURLs = []
        panel.dataSource = nil
        panel.delegate = nil
        removeKeyDownMonitor()
    }

    private func installKeyDownMonitor() {
        guard keyDownMonitor == nil else { return }

        keyDownMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode
            let blockedModifiers: NSEvent.ModifierFlags = [.command, .option, .control, .shift]
            let hasBlockedModifiers = !event.modifierFlags.intersection(blockedModifiers).isEmpty
            let handled = MainActor.assumeIsolated {
                guard let self,
                      let panel = QLPreviewPanel.shared(),
                      panel.isVisible,
                      !hasBlockedModifiers
                else {
                    return false
                }

                let direction: PreviewNavigationDirection
                switch keyCode {
                case 126:
                    direction = .previous
                case 125:
                    direction = .next
                default:
                    return false
                }

                return self.navigationHandler?(direction) == true
            }
            return handled ? nil : event
        }
    }

    private func removeKeyDownMonitor() {
        guard let keyDownMonitor else { return }
        NSEvent.removeMonitor(keyDownMonitor)
        self.keyDownMonitor = nil
    }
}
