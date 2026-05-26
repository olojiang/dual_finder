import AppKit
import Quartz

@MainActor
final class QuickLookPreviewService: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var previewURLs: [URL] = []

    func togglePreview(for urls: [URL]) {
        guard !urls.isEmpty, let panel = QLPreviewPanel.shared() else { return }

        if panel.isVisible, previewURLs == urls {
            panel.orderOut(nil)
            return
        }

        previewURLs = urls
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
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
    }
}
