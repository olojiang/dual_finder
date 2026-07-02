import AppKit
import SwiftUI
import DualFinderCore

struct FileTabDragHandler: NSViewRepresentable {
    let tabID: UUID
    let side: PaneSide
    let onSelect: () -> Void
    let onDragBegan: () -> Void
    let onDragEnded: () -> Void

    func makeNSView(context: Context) -> TabDragView {
        let view = TabDragView()
        view.tabID = tabID
        view.side = side
        view.onSelect = onSelect
        view.onDragBegan = onDragBegan
        view.onDragEnded = onDragEnded
        return view
    }

    func updateNSView(_ nsView: TabDragView, context: Context) {
        nsView.tabID = tabID
        nsView.side = side
        nsView.onSelect = onSelect
        nsView.onDragBegan = onDragBegan
        nsView.onDragEnded = onDragEnded
    }

    final class TabDragView: NSView, NSDraggingSource {
        var tabID = UUID()
        var side = PaneSide.left
        var onSelect: (() -> Void)?
        var onDragBegan: (() -> Void)?
        var onDragEnded: (() -> Void)?

        private var mouseDownLocation: NSPoint = .zero
        private var didStartDrag = false
        private static let dragThreshold: CGFloat = 4

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point) else { return nil }
            if let event = NSApp.currentEvent,
               event.type == .rightMouseDown || event.type == .rightMouseUp {
                return nil
            }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            guard event.buttonNumber == 0 else { return }
            mouseDownLocation = event.locationInWindow
            didStartDrag = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !didStartDrag else { return }
            let delta = hypot(
                event.locationInWindow.x - mouseDownLocation.x,
                event.locationInWindow.y - mouseDownLocation.y
            )
            guard delta >= Self.dragThreshold else { return }
            didStartDrag = true
            onDragBegan?()
            startTabDrag(with: event)
        }

        override func mouseUp(with event: NSEvent) {
            guard event.buttonNumber == 0 else { return }
            if !didStartDrag {
                onSelect?()
            }
            didStartDrag = false
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            switch context {
            case .outsideApplication:
                return []
            case .withinApplication:
                return .move
            @unknown default:
                return .move
            }
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            onDragEnded?()
        }

        private func startTabDrag(with event: NSEvent) {
            let payload = TabDragPayload.encode(tabID: tabID, side: side)
            let item = NSDraggingItem(pasteboardWriter: payload as NSString)
            item.setDraggingFrame(bounds, contents: nil)
            beginDraggingSession(with: [item], event: event, source: self)
        }
    }
}
