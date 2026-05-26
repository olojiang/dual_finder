import SwiftUI
import DualFinderCore

struct FilePaneView: View {
    let side: PaneSide
    @ObservedObject var model: DualFinderViewModel

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            tabStrip
            fileList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paneHeader: some View {
        HStack(spacing: 6) {
            IconButton(systemName: "chevron.up", help: "Go to parent folder") {
                model.navigateUp(side)
            }
            IconButton(systemName: "house", help: "Go home") {
                model.navigateHome(side)
            }
            IconButton(systemName: "folder.badge.plus", help: "Choose folder") {
                model.chooseFolder(for: side)
            }
            Text(model.pane(for: side).selectedURL.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            IconButton(systemName: "plus.square.on.square", help: "New tab") {
                model.addTab(on: side)
            }
            IconButton(systemName: "xmark.square", help: "Close tab") {
                model.closeSelectedTab(on: side)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private var tabStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(model.pane(for: side).tabs) { tab in
                    Button {
                        model.selectTab(tab.id, on: side)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                            Text(tab.url.lastPathComponent.isEmpty ? tab.url.path : tab.url.lastPathComponent)
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(tab.id == model.pane(for: side).selectedTabID ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .help(tab.url.path)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 6)
        }
    }

    private var fileList: some View {
        List(selection: model.bindingForSelection(side: side)) {
            ForEach(model.items(for: side)) { item in
                FileRow(item: item)
                    .tag(item.url)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        model.navigate(side, to: item.url)
                    }
            }
        }
        .contextMenu(forSelectionType: URL.self) { selection in
            Button("Copy to Other Pane") { model.copySelection(from: side) }
            Button("Move to Other Pane") { model.moveSelection(from: side) }
            Button("Move to Trash", role: .destructive) { model.trashSelection(from: side) }
        } primaryAction: { selection in
            if let first = selection.first {
                model.navigate(side, to: first)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                IconButton(systemName: "folder.badge.plus", help: "Create folder") {
                    model.createFolder(in: side)
                }
                IconButton(systemName: "trash", help: "Move selection to Trash") {
                    model.trashSelection(from: side)
                }
                IconButton(systemName: "arrow.clockwise", help: "Refresh pane") {
                    model.refresh(side)
                }
                Spacer()
                Text("\(model.items(for: side).count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(.bar)
        }
    }
}

private struct FileRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(item.isDirectoryLike ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(sizeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 76, alignment: .trailing)
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 126, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var iconName: String {
        switch item.kind {
        case .folder: "folder"
        case .package: "shippingbox"
        case .alias: "arrowshape.turn.up.right"
        case .file, .other: "doc"
        }
    }

    private var sizeText: String {
        guard let size = item.size, !item.isDirectoryLike else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var dateText: String {
        guard let modifiedAt = item.modifiedAt else { return "--" }
        return modifiedAt.formatted(date: .numeric, time: .shortened)
    }
}
