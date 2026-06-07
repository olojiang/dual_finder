import AppKit
import SwiftUI
import DualFinderCore

struct LayoutResizeHandle: View {
    enum Axis {
        case horizontal
        case vertical
    }

    let axis: Axis
    let onDrag: (CGFloat) -> Void
    var onDragEnded: (() -> Void)? = nil

    @State private var isHovering = false
    @State private var lastDragTranslation: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isHovering ? Color.accentColor.opacity(0.35) : Color.clear)
            .frame(
                width: axis == .vertical ? 5 : nil,
                height: axis == .horizontal ? 5 : nil
            )
            .frame(maxWidth: axis == .vertical ? 5 : .infinity, maxHeight: axis == .horizontal ? 5 : .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                isHovering = hovering
                if hovering {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let translation = axis == .vertical ? value.translation.width : value.translation.height
                        let delta = translation - lastDragTranslation
                        lastDragTranslation = translation
                        guard delta != 0 else { return }
                        onDrag(delta)
                    }
                    .onEnded { _ in
                        lastDragTranslation = 0
                        onDragEnded?()
                    }
            )
            .accessibilityLabel("Resize")
    }
}

struct FileListColumnLayout<Name: View, TypeColumn: View, SizeColumn: View, ModifiedColumn: View>: View {
    let columnWidths: FileListColumnWidths
    let showsResizeHandles: Bool
    let onResizeColumn: (FileListColumn, CGFloat) -> Void
    var onResizeEnded: (() -> Void)? = nil
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

            columnGap(for: .type)
            type()
                .frame(width: columnWidths.width(for: .type), alignment: .leading)

            columnGap(for: .size)
            size()
                .frame(width: columnWidths.width(for: .size), alignment: .trailing)

            columnGap(for: .modified)
            modified()
                .frame(width: columnWidths.width(for: .modified), alignment: .trailing)
        }
    }

    @ViewBuilder
    private func columnGap(for column: FileListColumn) -> some View {
        if showsResizeHandles {
            LayoutResizeHandle(axis: .vertical, onDrag: { delta in
                onResizeColumn(column, delta)
            }, onDragEnded: onResizeEnded)
        } else {
            Color.clear.frame(width: 5)
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

    var body: some View {
        HStack(spacing: 0) {
            sidebar()
                .frame(width: sidebarWidth)

            Divider()

            GeometryReader { geometry in
                let totalWidth = max(geometry.size.width, 1)
                let dividerWidth: CGFloat = 5
                let availableWidth = totalWidth - dividerWidth
                let leftWidth = availableWidth * leftPaneFraction

                HStack(spacing: 0) {
                    leftPane()
                        .frame(width: leftWidth)

                    LayoutResizeHandle(axis: .vertical, onDrag: { delta in
                        let nextFraction = leftPaneFraction + Double(delta / availableWidth)
                        onResizeLeftPaneFraction(nextFraction)
                    }, onDragEnded: onResizeLeftPaneEnded)

                    rightPane()
                        .frame(width: availableWidth - leftWidth)
                }
            }

            trailing()
        }
    }
}
