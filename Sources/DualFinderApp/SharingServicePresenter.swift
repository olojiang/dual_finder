import AppKit
import Foundation

@MainActor
enum SharingServicePresenter {
    static func presentSharePicker(for urls: [URL]) {
        let items: [Any] = urls.map { $0 as NSURL }
        guard !items.isEmpty else { return }

        let picker = NSSharingServicePicker(items: items)
        guard let window = NSApp.keyWindow, let view = window.contentView else { return }

        let mouse = window.mouseLocationOutsideOfEventStream
        let anchor = NSRect(
            x: mouse.x,
            y: mouse.y,
            width: 1,
            height: 1
        )
        picker.show(relativeTo: anchor, of: view, preferredEdge: .minY)
    }
}
