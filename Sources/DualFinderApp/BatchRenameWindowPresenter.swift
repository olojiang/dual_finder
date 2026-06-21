import AppKit
import SwiftUI

struct BatchRenameWindowPresenter: NSViewRepresentable {
    let request: BatchRenameDialogRequest?
    let model: DualFinderViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.update(request: request, model: model, parentWindow: view.window)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.closeWindow()
    }

    @MainActor
    final class Coordinator: NSObject, NSWindowDelegate {
        private weak var model: DualFinderViewModel?
        private var window: NSWindow?
        private var requestID: UUID?

        func update(request: BatchRenameDialogRequest?, model: DualFinderViewModel, parentWindow: NSWindow?) {
            self.model = model

            guard let request else {
                closeWindow()
                return
            }

            if requestID == request.id, window != nil {
                window?.makeKeyAndOrderFront(nil)
                return
            }

            closeWindow()
            requestID = request.id
            let window = makeWindow(for: request, model: model)
            self.window = window
            position(window, relativeTo: parentWindow)
            window.makeKeyAndOrderFront(nil)
        }

        func closeWindow() {
            guard let window else { return }
            window.delegate = nil
            window.close()
            self.window = nil
            requestID = nil
        }

        func windowWillClose(_ notification: Notification) {
            window = nil
            requestID = nil
            model?.batchRenameDialogRequest = nil
        }

        private func makeWindow(for request: BatchRenameDialogRequest, model: DualFinderViewModel) -> NSWindow {
            let hostingView = NSHostingView(
                rootView: BatchRenameDialog(
                    model: model,
                    side: request.side,
                    onDismiss: { [weak self] in
                        self?.model?.batchRenameDialogRequest = nil
                    },
                    onSizeChange: { [weak self] size in
                        self?.resizeWindow(to: size)
                    }
                )
            )

            let window = NSWindow(
                contentRect: NSRect(origin: .zero, size: hostingView.fittingSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Batch Rename"
            window.contentView = hostingView
            window.delegate = self
            window.isReleasedWhenClosed = false
            window.isMovableByWindowBackground = true
            window.tabbingMode = .disallowed
            window.minSize = NSSize(width: 760, height: 520)
            return window
        }

        private func resizeWindow(to size: CGSize) {
            guard let window else { return }
            var frame = window.frame
            let contentRect = window.contentRect(forFrameRect: frame)
            let heightDelta = size.height - contentRect.height
            let nextFrame = window.frameRect(forContentRect: NSRect(
                x: contentRect.minX,
                y: contentRect.minY - heightDelta,
                width: size.width,
                height: size.height
            ))
            frame.origin.y = nextFrame.origin.y
            frame.size = nextFrame.size
            window.setFrame(frame, display: true, animate: true)
        }

        private func position(_ window: NSWindow, relativeTo parentWindow: NSWindow?) {
            guard let parentWindow else {
                window.center()
                return
            }

            let parentFrame = parentWindow.frame
            let frame = window.frame
            let origin = NSPoint(
                x: parentFrame.midX - frame.width / 2,
                y: parentFrame.midY - frame.height / 2
            )
            window.setFrameOrigin(origin)
        }
    }
}
