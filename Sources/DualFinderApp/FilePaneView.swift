import AppKit
import SwiftUI
import DualFinderCore

struct FilePaneView: View {
    let side: PaneSide
    @ObservedObject var model: DualFinderViewModel
    @State private var renamingURL: URL?
    @State private var pendingRenameURL: URL?
    @State private var renameText = ""
    @State private var isEditingPath = false
    @State private var pathText = ""
    @FocusState private var isFileListFocused: Bool
    @FocusState private var isPathFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            paneHeader
            tabStrip
            fileList
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: model.pathEditRequest) { _, request in
            guard request?.side == side else { return }
            beginPathEditing()
        }
        .onChange(of: model.pane(for: side).selectedURL) { _, url in
            guard !isEditingPath else { return }
            pathText = url.path
        }
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
            pathControl
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

    @ViewBuilder
    private var pathControl: some View {
        if isEditingPath {
            TextField("Folder path", text: $pathText)
                .textFieldStyle(.plain)
                .font(.system(.caption, design: .monospaced))
                .focused($isPathFieldFocused)
                .onSubmit(commitPathEditing)
                .onKeyPress(.escape, phases: .down) { _ in
                    cancelPathEditing()
                    return .handled
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear {
                    isPathFieldFocused = true
                }
        } else {
            Text(model.pane(for: side).selectedURL.path)
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    beginPathEditing()
                }
        }
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
        VStack(spacing: 0) {
            sortHeader
            List(selection: model.bindingForSelection(side: side)) {
                ForEach(model.items(for: side)) { item in
                    FileRow(
                        item: item,
                        isRenaming: renamingURL == item.url,
                        renameText: $renameText,
                        commitRename: commitRename,
                        cancelRename: cancelRename
                    )
                        .tag(item.url)
                        .contentShape(Rectangle())
                        .overlay {
                            if renamingURL != item.url {
                                RowMouseHandler(
                                    mouseDown: { modifierFlags in
                                        selectItemFromRowMouseDown(item.url, modifierFlags: modifierFlags)
                                    },
                                    doubleClick: {
                                        activateItem(item.url)
                                    }
                                )
                            }
                        }
                }
            }
            .focused($isFileListFocused)
            .onKeyPress(.return, phases: .down) { keyPress in
                guard keyPress.modifiers.isEmpty else { return .ignored }
                return beginRenamingSelectedItem() ? .handled : .ignored
            }
            .onKeyPress(KeyEquivalent("o"), phases: .down) { keyPress in
                guard keyPress.modifiers.contains(.command) else { return .ignored }
                model.openSelectionWithDefaultApp(on: side)
                return .handled
            }
            .onKeyPress(KeyEquivalent("c"), phases: .down) { keyPress in
                guard keyPress.modifiers.contains(.command),
                      keyPress.modifiers.contains(.option),
                      renamingURL == nil
                else { return .ignored }
                model.copyAbsolutePaths(model.pane(for: side).selectedItemURLs, on: side)
                return .handled
            }
            .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { keyPress in
                guard keyPress.modifiers.contains(.command), renamingURL == nil else { return .ignored }
                if keyPress.modifiers.contains(.shift) {
                    model.emptyTrash()
                } else {
                    model.trashSelection(from: side)
                }
                return .handled
            }
            .onKeyPress(.space, phases: .down) { keyPress in
                guard renamingURL == nil else { return .ignored }
                if keyPress.modifiers.contains(.control) {
                    model.calculateSelectedFolderSizes(on: side)
                    return .handled
                }
                guard keyPress.modifiers.isEmpty else { return .ignored }
                model.previewSelection(on: side)
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow], phases: .down) { keyPress in
                guard keyPress.modifiers.contains(.command) else { return .ignored }
                switch keyPress.key {
                case .upArrow:
                    model.navigateUp(side)
                    return .handled
                case .downArrow:
                    model.navigateIntoSelectedDirectory(side)
                    return .handled
                default:
                    return .ignored
                }
            }
            .contextMenu(forSelectionType: URL.self) { selection in
                Button("Copy Absolute Path") { model.copyAbsolutePaths(selection, on: side) }
                Button("Open in Ghostty or Terminal") { model.openInTerminal(selection, on: side) }
                Divider()
                Button("Copy to Other Pane") { model.copySelection(from: side) }
                Button("Move to Other Pane") { model.moveSelection(from: side) }
                Button("Move to Trash", role: .destructive) { model.trashSelection(from: side) }
            } primaryAction: { selection in
                model.activateFirstItem(in: selection, on: side)
            }
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 8) {
                    IconButton(systemName: "folder.badge.plus", help: "Create folder") {
                        if let created = model.createFolder(in: side) {
                            queueRename(created)
                        }
                    }
                    IconButton(systemName: "trash", help: "Move selection to Trash") {
                        model.trashSelection(from: side)
                    }
                    IconButton(systemName: "arrow.clockwise", help: "Refresh pane") {
                        model.refresh(side)
                    }
                    IconButton(systemName: "ruler", help: "Calculate selected folder size (Ctrl-Space)") {
                        model.calculateSelectedFolderSizes(on: side)
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
        .onChange(of: model.items(for: side)) { _, _ in
            beginPendingRenameIfReady()
        }
        .onChange(of: model.pane(for: side).selectedItemURLs) { _, selection in
            guard let renamingURL, !selection.contains(renamingURL) else { return }
            clearRenameState()
        }
    }

    private var sortHeader: some View {
        HStack(spacing: 8) {
            SortHeaderButton(title: "Name", field: .name, rule: model.sortRule(for: side)) {
                model.selectSortField(.name, for: side)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            SortHeaderButton(title: "Type", field: .type, rule: model.sortRule(for: side)) {
                model.selectSortField(.type, for: side)
            }
            .frame(width: 112, alignment: .leading)
            SortHeaderButton(title: "Size", field: .size, rule: model.sortRule(for: side)) {
                model.selectSortField(.size, for: side)
            }
            .frame(width: 86, alignment: .trailing)
            SortHeaderButton(title: "Modified", field: .modifiedAt, rule: model.sortRule(for: side)) {
                model.selectSortField(.modifiedAt, for: side)
            }
            .frame(width: 126, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(.bar)
    }

    private func beginRenamingSelectedItem() -> Bool {
        guard renamingURL == nil else { return false }
        let selected = model.pane(for: side).selectedItemURLs
        guard selected.count == 1,
              let item = model.items(for: side).first(where: { selected.contains($0.url) }) else {
            return false
        }

        beginRenaming(item)
        model.isInlineRenaming = true
        return true
    }

    private func beginRenaming(_ url: URL) {
        if let item = model.items(for: side).first(where: { $0.url == url }) {
            beginRenaming(item)
        } else {
            renamingURL = url
            renameText = url.lastPathComponent
        }
        model.isInlineRenaming = true
    }

    private func queueRename(_ url: URL) {
        pendingRenameURL = url
        DispatchQueue.main.async {
            beginPendingRenameIfReady()
        }
    }

    private func beginPendingRenameIfReady() {
        guard let pendingRenameURL,
              model.items(for: side).contains(where: { $0.url == pendingRenameURL }) else {
            return
        }
        self.pendingRenameURL = nil
        beginRenaming(pendingRenameURL)
    }

    private func beginRenaming(_ item: FileItem) {
        renamingURL = item.url
        renameText = item.name
    }

    private func commitRename() {
        guard let renamingURL else { return }
        let newName = renameText
        clearRenameState()
        model.renameItem(renamingURL, to: newName, on: side)
        restoreFileListFocus()
    }

    private func cancelRename() {
        clearRenameState()
        restoreFileListFocus()
    }

    private func clearRenameState() {
        renamingURL = nil
        pendingRenameURL = nil
        renameText = ""
        model.isInlineRenaming = false
    }

    private func beginPathEditing() {
        model.activatePane(side)
        if !isEditingPath {
            pathText = model.pane(for: side).selectedURL.path
            isEditingPath = true
        }
        DispatchQueue.main.async {
            isPathFieldFocused = true
        }
    }

    private func commitPathEditing() {
        guard model.navigateToFolderPath(pathText, on: side) else {
            isPathFieldFocused = true
            return
        }

        isEditingPath = false
        pathText = model.pane(for: side).selectedURL.path
        restoreFileListFocus()
    }

    private func cancelPathEditing() {
        isEditingPath = false
        pathText = model.pane(for: side).selectedURL.path
        restoreFileListFocus()
    }

    private func activateItem(_ url: URL) {
        guard renamingURL == nil else { return }
        model.activateItem(url, on: side)
        restoreFileListFocus()
    }

    private func selectItemFromRowMouseDown(_ url: URL, modifierFlags: NSEvent.ModifierFlags) {
        guard renamingURL == nil else { return }

        isFileListFocused = true
        model.activatePane(side)

        if modifierFlags.contains(.command) {
            model.toggleItemSelection(url, on: side)
            return
        }

        if modifierFlags.contains(.shift) {
            model.extendSelection(to: url, on: side)
            return
        }

        model.selectItem(url, on: side)
    }

    private func restoreFileListFocus() {
        DispatchQueue.main.async {
            isFileListFocused = true
        }
    }
}

private struct RowMouseHandler: NSViewRepresentable {
    let mouseDown: (NSEvent.ModifierFlags) -> Void
    let doubleClick: () -> Void

    func makeNSView(context: Context) -> MouseHandlingView {
        let view = MouseHandlingView()
        view.mouseDownAction = mouseDown
        view.doubleClickAction = doubleClick
        return view
    }

    func updateNSView(_ nsView: MouseHandlingView, context: Context) {
        nsView.mouseDownAction = mouseDown
        nsView.doubleClickAction = doubleClick
    }

    final class MouseHandlingView: NSView {
        var mouseDownAction: ((NSEvent.ModifierFlags) -> Void)?
        var doubleClickAction: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func hitTest(_ point: NSPoint) -> NSView? {
            bounds.contains(point) ? self : nil
        }

        override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
            true
        }

        override func mouseDown(with event: NSEvent) {
            if event.clickCount >= 2 {
                doubleClickAction?()
            } else {
                mouseDownAction?(event.modifierFlags)
            }
        }

        override func rightMouseDown(with event: NSEvent) {
            mouseDownAction?(event.modifierFlags)
            super.rightMouseDown(with: event)
        }
    }
}

private struct FileRow: View {
    let item: FileItem
    let isRenaming: Bool
    @Binding var renameText: String
    let commitRename: () -> Void
    let cancelRename: () -> Void
    @FocusState private var isRenameFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(item.isDirectoryLike ? Color.accentColor : Color.secondary)
                .frame(width: 20)
            nameView
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.type)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 112, alignment: .leading)
            Text(sizeText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 86, alignment: .trailing)
            Text(dateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 126, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var nameView: some View {
        if isRenaming {
            TextField("Name", text: $renameText)
                .textFieldStyle(.plain)
                .focused($isRenameFocused)
                .onSubmit(commitRename)
                .onKeyPress(.escape, phases: .down) { _ in
                    cancelRename()
                    return .handled
                }
                .onAppear {
                    isRenameFocused = true
                    DispatchQueue.main.async {
                        NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    }
                }
        } else {
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
        }
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
        guard let size = item.size else { return "--" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private var dateText: String {
        guard let modifiedAt = item.modifiedAt else { return "--" }
        return modifiedAt.formatted(date: .numeric, time: .shortened)
    }
}

private struct SortHeaderButton: View {
    let title: String
    let field: FileSortField
    let rule: FileSortRule
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                Text(title)
                    .lineLimit(1)
                Image(systemName: iconName)
                    .font(.caption2)
                    .opacity(rule.field == field ? 1 : 0)
            }
            .frame(maxWidth: .infinity, alignment: alignment)
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var iconName: String {
        rule.direction == .ascending ? "chevron.up" : "chevron.down"
    }

    private var alignment: Alignment {
        field == .size || field == .modifiedAt ? .trailing : .leading
    }

    private var helpText: String {
        "Sort by \(title)"
    }
}
