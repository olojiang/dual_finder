import AppKit
import SwiftUI
import DualFinderCore

struct LayoutResizeHandle: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    let length: CGFloat?
    let onDrag: (CGFloat) -> Void
    var onDragEnded: (() -> Void)? = nil
    var visualThickness: CGFloat? = nil
    var visualAlignment: Alignment = .center

    @State private var isHovering = false
    @State private var isDragging = false

    var body: some View {
        Color.clear
            .frame(width: axis == .vertical ? 5 : length)
            .frame(maxWidth: axis == .vertical ? 5 : .infinity)
            .frame(height: axis == .horizontal ? 5 : length)
            .frame(maxHeight: axis == .horizontal ? 5 : (length == nil ? .infinity : length))
            .overlay(alignment: visualAlignment) {
                Rectangle()
                    .fill(handleColor)
                    .frame(
                        width: axis == .vertical ? (visualThickness ?? 5) : nil,
                        height: axis == .horizontal ? (visualThickness ?? 5) : nil
                    )
            }
            .contentShape(Rectangle())
            .overlay {
                LayoutResizeTrackingView(
                    axis: axis,
                    onDrag: onDrag,
                    onDragEnded: onDragEnded,
                    onHoverChanged: { isHovering = $0 },
                    onDraggingChanged: { isDragging = $0 }
                )
            }
            .accessibilityLabel("Resize")
    }

    private var handleColor: Color {
        if isDragging {
            return Color.accentColor.opacity(0.7)
        }
        if isHovering {
            return Color.accentColor.opacity(0.45)
        }
        return Color.secondary.opacity(0.16)
    }

}

private struct LayoutResizeTrackingView: NSViewRepresentable {
    let axis: LayoutResizeHandle.Axis
    let onDrag: (CGFloat) -> Void
    let onDragEnded: (() -> Void)?
    let onHoverChanged: (Bool) -> Void
    let onDraggingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> LayoutResizeTrackingNSView {
        let view = LayoutResizeTrackingNSView(frame: .zero)
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: LayoutResizeTrackingNSView, context: Context) {
        nsView.axis = axis
        nsView.onDrag = onDrag
        nsView.onDragEnded = onDragEnded
        nsView.onHoverChanged = onHoverChanged
        nsView.onDraggingChanged = onDraggingChanged
    }
}

private final class LayoutResizeTrackingNSView: NSView {
    var axis: LayoutResizeHandle.Axis = .vertical {
        didSet {
            window?.invalidateCursorRects(for: self)
        }
    }
    var onDrag: (CGFloat) -> Void = { _ in }
    var onDragEnded: (() -> Void)?
    var onHoverChanged: (Bool) -> Void = { _ in }
    var onDraggingChanged: (Bool) -> Void = { _ in }

    private var trackingArea: NSTrackingArea?

    override var acceptsFirstResponder: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let options: NSTrackingArea.Options = [
            .activeInKeyWindow,
            .mouseEnteredAndExited,
            .inVisibleRect
        ]
        let area = NSTrackingArea(rect: bounds, options: options, owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: resizeCursor)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        onDraggingChanged(true)
        var didDrag = false
        var previousLocation = event.locationInWindow

        while true {
            guard let nextEvent = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) else {
                break
            }

            if nextEvent.type == .leftMouseUp {
                break
            }

            let location = nextEvent.locationInWindow
            let delta = axis == .vertical
                ? location.x - previousLocation.x
                : location.y - previousLocation.y
            previousLocation = location
            guard delta != 0 else { continue }
            didDrag = true
            onDrag(delta)
        }

        onDraggingChanged(false)
        if didDrag {
            onDragEnded?()
        }
    }

    private var resizeCursor: NSCursor {
        switch axis {
        case .horizontal: .resizeUpDown
        case .vertical: .resizeLeftRight
        }
    }
}

struct FileListColumnLayout<Name: View, TypeColumn: View, SizeColumn: View, ModifiedColumn: View>: View {
    let columnWidths: FileListColumnWidths
    let showsResizeHandles: Bool
    let onResizeColumn: (FileListColumn, CGFloat) -> Void
    var onResizeEnded: (() -> Void)? = nil
    @State private var activeResizeBoundary: FileListColumnBoundary?
    @State private var dragStartWidths: FileListColumnWidths?
    @State private var dragAccumulatedDelta: CGFloat = 0
    @ViewBuilder let name: () -> Name
    @ViewBuilder let type: () -> TypeColumn
    @ViewBuilder let size: () -> SizeColumn
    @ViewBuilder let modified: () -> ModifiedColumn

    init(
        columnWidths: FileListColumnWidths,
        showsResizeHandles: Bool = false,
        onResizeColumn: @escaping (FileListColumn, CGFloat) -> Void = { _, _ in },
        onResizeEnded: (() -> Void)? = nil,
        @ViewBuilder name: @escaping () -> Name,
        @ViewBuilder type: @escaping () -> TypeColumn,
        @ViewBuilder size: @escaping () -> SizeColumn,
        @ViewBuilder modified: @escaping () -> ModifiedColumn
    ) {
        self.columnWidths = columnWidths
        self.showsResizeHandles = showsResizeHandles
        self.onResizeColumn = onResizeColumn
        self.onResizeEnded = onResizeEnded
        self.name = name
        self.type = type
        self.size = size
        self.modified = modified
    }

    var body: some View {
        HStack(spacing: 0) {
            name()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 4)

            columnGap(.afterName)
            type()
                .frame(width: columnWidths.width(for: .type), alignment: .leading)

            columnGap(.afterType)
            size()
                .frame(width: columnWidths.width(for: .size), alignment: .trailing)

            columnGap(.afterSize)
            modified()
                .frame(width: columnWidths.width(for: .modified), alignment: .trailing)

            Color.clear.frame(width: 5)
        }
        .overlay(alignment: .leading) {
            GeometryReader { geometry in
                if let activeResizeBoundary,
                   let previewWidths {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.85))
                        .frame(width: 1)
                        .offset(x: boundaryPosition(activeResizeBoundary, widths: previewWidths, totalWidth: geometry.size.width))
                        .allowsHitTesting(false)
                }
            }
        }
    }

    @ViewBuilder
    private func columnGap(_ boundary: FileListColumnBoundary) -> some View {
        if showsResizeHandles {
            LayoutResizeHandle(
                axis: .vertical,
                length: 16,
                onDrag: { delta in
                    beginColumnDragIfNeeded(boundary)
                    dragAccumulatedDelta += delta
                },
                onDragEnded: {
                    let totalColumnDelta = CGFloat(boundary.columnDelta(forDragDelta: Double(dragAccumulatedDelta)))
                    if totalColumnDelta != 0 {
                        onResizeColumn(boundary.resizedColumn, totalColumnDelta)
                    }
                    resetColumnDrag()
                    onResizeEnded?()
                },
                visualThickness: 1,
                visualAlignment: .trailing
            )
        } else {
            Color.clear.frame(width: 5)
        }
    }

    private var previewWidths: FileListColumnWidths? {
        guard let activeResizeBoundary,
              var widths = dragStartWidths
        else {
            return nil
        }
        let totalColumnDelta = activeResizeBoundary.columnDelta(forDragDelta: Double(dragAccumulatedDelta))
        widths.adjust(activeResizeBoundary.resizedColumn, by: totalColumnDelta)
        return widths
    }

    private func beginColumnDragIfNeeded(_ boundary: FileListColumnBoundary) {
        guard activeResizeBoundary == nil else { return }
        activeResizeBoundary = boundary
        dragStartWidths = columnWidths
        dragAccumulatedDelta = 0
    }

    private func resetColumnDrag() {
        activeResizeBoundary = nil
        dragStartWidths = nil
        dragAccumulatedDelta = 0
    }

    private func boundaryPosition(
        _ boundary: FileListColumnBoundary,
        widths: FileListColumnWidths,
        totalWidth: CGFloat
    ) -> CGFloat {
        let trailingPadding: CGFloat = 5
        let handleWidth: CGFloat = 5
        switch boundary {
        case .afterName:
            return totalWidth
                - trailingPadding
                - widths.width(for: .modified)
                - handleWidth
                - widths.width(for: .size)
                - handleWidth
                - widths.width(for: .type)
                - handleWidth
        case .afterType:
            return totalWidth
                - trailingPadding
                - widths.width(for: .modified)
                - handleWidth
                - widths.width(for: .size)
                - handleWidth
        case .afterSize:
            return totalWidth
                - trailingPadding
                - widths.width(for: .modified)
                - handleWidth
        }
    }
}

struct DualPaneSplitLayout<Sidebar: View, LeftPane: View, RightPane: View, Trailing: View>: View {
    let sidebarWidth: CGFloat
    let leftPaneFraction: Double
    let onResizeLeftPaneFraction: (Double) -> Void
    var onResizeLeftPaneEnded: (() -> Void)? = nil
    @ViewBuilder let sidebar: () -> Sidebar
    @ViewBuilder let leftPane: () -> LeftPane
    @ViewBuilder let rightPane: () -> RightPane
    @ViewBuilder let trailing: () -> Trailing

    @State private var dragStartFraction: Double?
    @State private var dragStartAvailableWidth: CGFloat = 0
    @State private var dragAccumulatedDelta: CGFloat = 0
    @State private var dragPreviewFraction: Double?

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: sidebarWidth)

            Divider()

            GeometryReader { geometry in
                let totalWidth = max(geometry.size.width, 1)
                let dividerWidth: CGFloat = 5
                let availableWidth = max(totalWidth - dividerWidth, 1)
                let leftWidth = availableWidth * leftPaneFraction
                let previewLeftWidth = availableWidth * (dragPreviewFraction ?? leftPaneFraction)

                ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        leftPane()
                            .frame(width: leftWidth)

                        LayoutResizeHandle(axis: .vertical, length: nil, onDrag: { delta in
                            beginDragIfNeeded(availableWidth: availableWidth)
                            dragAccumulatedDelta += delta
                            let nextFraction = (dragStartFraction ?? leftPaneFraction)
                                + Double(dragAccumulatedDelta / dragStartAvailableWidth)
                            dragPreviewFraction = UILayoutPreferences.clampedFraction(nextFraction)
                        }, onDragEnded: {
                            if let dragPreviewFraction {
                                onResizeLeftPaneFraction(dragPreviewFraction)
                            }
                            resetDragState()
                            onResizeLeftPaneEnded?()
                        })

                        rightPane()
                            .frame(width: max(0, availableWidth - leftWidth))
                    }

                    if dragPreviewFraction != nil {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.85))
                            .frame(width: 1)
                            .offset(x: previewLeftWidth + dividerWidth / 2)
                            .allowsHitTesting(false)
                    }
                }
            }

            trailing()
        }
    }

    private func beginDragIfNeeded(availableWidth: CGFloat) {
        guard dragStartFraction == nil else { return }
        dragStartFraction = leftPaneFraction
        dragStartAvailableWidth = max(availableWidth, 1)
        dragAccumulatedDelta = 0
    }

    private func resetDragState() {
        dragStartFraction = nil
        dragStartAvailableWidth = 0
        dragAccumulatedDelta = 0
        dragPreviewFraction = nil
    }
}
