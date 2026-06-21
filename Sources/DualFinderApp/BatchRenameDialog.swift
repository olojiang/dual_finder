import SwiftUI
import AppKit
import DualFinderCore

private enum BatchRenameDialogMode: String, CaseIterable, Identifiable {
    case numbering = "Number"
    case replace = "Replace"
    case extensionChange = "Extension"
    case metadata = "Metadata"

    var id: Self { self }
}

struct BatchRenameDialog: View {
    @ObservedObject var model: DualFinderViewModel
    let side: PaneSide
    var onDismiss: (@MainActor () -> Void)?
    var onSizeChange: (@MainActor (CGSize) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var mode: BatchRenameDialogMode = .replace
    @State private var prefix = "File "
    @State private var suffix = ""
    @State private var startNumber = 1
    @State private var padding = 2
    @State private var includeOriginalName = false
    @State private var search = ""
    @State private var replacement = ""
    @State private var caseSensitive = true
    @State private var useRegularExpression = false
    @State private var newExtension = ""
    @State private var metadataTemplate = "{modifiedDate}_{modifiedTime}_{base}{extWithDot}"
    @State private var isExpanded = false
    @State private var findHistory = BatchRenameHistoryStore().values(for: .find)
    @State private var replaceHistory = BatchRenameHistoryStore().values(for: .replace)
    @State private var previewResult: Result<[BatchRenamePreview], Error> = .success([])

    private let historyStore = BatchRenameHistoryStore()
    private let statusColumnWidth: CGFloat = 96

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                modeList
                Divider()
                VStack(spacing: 0) {
                    controls
                    Divider()
                    preview
                }
            }
            Divider()
            footer
        }
        .frame(width: dialogSize.width, height: dialogSize.height)
        .onAppear {
            refreshPreview()
            onSizeChange?(dialogSize)
        }
        .onChange(of: rule) { _, _ in
            refreshPreview()
        }
        .onChange(of: selectedItemsForPreview) { _, _ in
            refreshPreview()
        }
        .onChange(of: dialogSize) { _, newSize in
            onSizeChange?(newSize)
        }
    }

    private var header: some View {
        HStack {
            Text("Batch Rename")
                .font(.headline)
            Spacer()
            Button {
                isExpanded.toggle()
            } label: {
                Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help(isExpanded ? "Use compact preview" : "Use larger preview")
            .accessibilityLabel(isExpanded ? "Use compact preview" : "Use larger preview")
            Text("\(model.selectedItems(on: side).count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var modeList: some View {
        VStack(spacing: 2) {
            ForEach(BatchRenameDialogMode.allCases) { item in
                Button {
                    mode = item
                } label: {
                    Text(item.rawValue)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(mode == item ? Color.accentColor.opacity(0.16) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(8)
        .background(.bar)
        .frame(width: 150)
    }

    @ViewBuilder
    private var controls: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch mode {
            case .numbering:
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    labeledTextField("Prefix", text: $prefix)
                    labeledTextField("Suffix", text: $suffix)
                    labeledNumberField("Start", value: $startNumber)
                    labeledNumberField("Padding", value: $padding)
                    GridRow {
                        Text("")
                        Toggle("Include original name", isOn: $includeOriginalName)
                    }
                }
            case .replace:
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    labeledHistoryTextField("Find", text: $search, history: findHistory, field: .find)
                    labeledHistoryTextField("Replace", text: $replacement, history: replaceHistory, field: .replace)
                    GridRow {
                        Text("")
                        HStack(spacing: 16) {
                            Toggle("Regex", isOn: $useRegularExpression)
                            Toggle("Case sensitive", isOn: $caseSensitive)
                                .disabled(useRegularExpression)
                        }
                    }
                }
            case .extensionChange:
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    labeledTextField("Extension", text: $newExtension)
                }
            case .metadata:
                VStack(alignment: .leading, spacing: 10) {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                        labeledTextField("Template", text: $metadataTemplate)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                            .frame(width: 98)
                        Menu("Insert Token") {
                            tokenButton("Index", token: "{index}")
                            tokenButton("Name", token: "{name}")
                            tokenButton("Base Name", token: "{base}")
                            tokenButton("Extension", token: "{extWithDot}")
                            tokenButton("Modified Date", token: "{modifiedDate}")
                            tokenButton("Modified Time", token: "{modifiedTime}")
                            tokenButton("Created Date", token: "{createdDate}")
                            tokenButton("Created Time", token: "{createdTime}")
                            tokenButton("Size", token: "{size}")
                            tokenButton("Type", token: "{type}")
                            tokenButton("Kind", token: "{kind}")
                        }
                        .menuStyle(.button)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: some View {
        VStack(spacing: 0) {
            previewHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    switch previewResult {
                    case let .success(previews):
                        ForEach(previews) { item in
                            previewRow(item)
                            Divider()
                        }
                    case let .failure(error):
                        Text(error.localizedDescription)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                    }
                }
            }
        }
    }

    private var previewHeader: some View {
        HStack(spacing: 10) {
            Text("Original")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("New")
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Status")
                .frame(width: statusColumnWidth, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func previewRow(_ item: BatchRenamePreview) -> some View {
        HStack(spacing: 10) {
            Text(item.originalName)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(item.originalName)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.newName)
                .lineLimit(2)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(item.newName)
                .foregroundStyle(item.status.allowsApply ? Color.primary : Color.red)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(statusText(for: item))
                .font(.caption)
                .foregroundStyle(item.status.allowsApply ? Color.secondary : Color.red)
                .frame(width: statusColumnWidth, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                closeDialog()
            }
            Button("Rename") {
                if case let .success(previews) = previewResult {
                    recordCurrentHistory()
                    model.applyBatchRename(previews, on: side)
                    closeDialog()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
        .padding(14)
    }

    private var canApply: Bool {
        guard case let .success(previews) = previewResult else { return false }
        return previews.contains(where: \.isChanged) && previews.allSatisfy { $0.status.allowsApply }
    }

    private var selectedItemsForPreview: [FileItem] {
        model.selectedItems(on: side)
    }

    private func refreshPreview() {
        previewResult = Result {
            try BatchRenamePlanner().previews(for: selectedItemsForPreview, rule: rule)
        }
    }

    private var rule: BatchRenameRule {
        switch mode {
        case .numbering:
            return .numbering(
                prefix: prefix,
                suffix: suffix,
                start: startNumber,
                padding: padding,
                includeOriginalName: includeOriginalName
            )
        case .replace:
            if useRegularExpression {
                return .regularExpression(pattern: search, replacement: replacement)
            }
            return .literalReplace(search: search, replacement: replacement, caseSensitive: caseSensitive)
        case .extensionChange:
            return .changeExtension(newExtension)
        case .metadata:
            return .metadataTemplate(metadataTemplate)
        }
    }

    private var dialogSize: CGSize {
        let visibleSize = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1_440, height: 900)
        let compactWidth = min(1_120, max(960, visibleSize.width * 0.82))
        let compactHeight = min(720, max(640, visibleSize.height * 0.78))

        guard isExpanded else {
            return CGSize(width: compactWidth, height: compactHeight)
        }

        return CGSize(
            width: min(1_600, max(compactWidth, visibleSize.width * 0.94)),
            height: min(1_000, max(compactHeight, visibleSize.height * 0.90))
        )
    }

    private func labeledTextField(_ label: String, text: Binding<String>) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 420, maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func labeledHistoryTextField(
        _ label: String,
        text: Binding<String>,
        history: [String],
        field: BatchRenameHistoryStore.Field
    ) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
            TextField(label, text: text)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 420, maxWidth: .infinity)
        }

        if !history.isEmpty {
            GridRow {
                Text("")
                BatchRenameHistoryChips(
                    history: history,
                    onSelect: { value in
                        text.wrappedValue = value
                        updateHistory(field, historyStore.record(value, for: field))
                    },
                    onDelete: { value in
                        updateHistory(field, historyStore.remove(value, for: field))
                    }
                )
                .frame(minWidth: 420, maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func labeledNumberField(_ label: String, value: Binding<Int>) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .frame(width: 86, alignment: .trailing)
            TextField(label, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .frame(width: 120)
        }
    }

    private func statusText(for item: BatchRenamePreview) -> String {
        switch item.status {
        case .unchanged:
            "Unchanged"
        case .ready:
            "Ready"
        case .emptyName:
            "Empty"
        case .invalidName:
            "Invalid"
        case .duplicateDestination:
            "Duplicate"
        case .destinationExists:
            "Exists"
        }
    }

    private func tokenButton(_ title: String, token: String) -> some View {
        Button(title) {
            metadataTemplate += token
        }
    }

    private func recordCurrentHistory() {
        switch mode {
        case .replace:
            updateHistory(.find, historyStore.record(search, for: .find))
            updateHistory(.replace, historyStore.record(replacement, for: .replace))
        case .numbering, .extensionChange, .metadata:
            break
        }
    }

    private func updateHistory(_ field: BatchRenameHistoryStore.Field, _ values: [String]) {
        switch field {
        case .find:
            findHistory = values
        case .replace:
            replaceHistory = values
        }
    }

    private func closeDialog() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }
}

private struct BatchRenameHistoryChips: View {
    let history: [String]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        WrappingHStack(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(history, id: \.self) { value in
                BatchRenameHistoryChip(value: value, onSelect: onSelect, onDelete: onDelete)
            }
        }
        .padding(.top, -3)
    }
}

private struct BatchRenameHistoryChip: View {
    let value: String
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            Button {
                onSelect(value)
            } label: {
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220)
            }
            .buttonStyle(.plain)
            .help(value)

            Button {
                onDelete(value)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete")
            .accessibilityLabel("Delete \(value)")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.secondary.opacity(0.18))
        }
    }
}

private struct WrappingHStack: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, proposalWidth: proposal.width ?? .infinity)
        let measuredWidth = rows.map(\.width).max() ?? 0
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? measuredWidth
        return CGSize(
            width: width,
            height: rows.last.map { $0.y + $0.height } ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = rows(for: subviews, proposalWidth: bounds.width)
        for row in rows {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(item.size)
                )
            }
        }
    }

    private func rows(for subviews: Subviews, proposalWidth: CGFloat) -> [Row] {
        guard !subviews.isEmpty else { return [] }

        let maxWidth = proposalWidth.isFinite ? max(0, proposalWidth) : .infinity
        var rows: [Row] = []
        var current = Row(y: 0)

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = current.items.isEmpty ? 0 : current.width + horizontalSpacing

            if !current.items.isEmpty, nextX + size.width > maxWidth {
                rows.append(current)
                current = Row(y: current.y + current.height + verticalSpacing)
            }

            let x = current.items.isEmpty ? 0 : current.width + horizontalSpacing
            current.items.append(Item(index: index, x: x, size: size))
            current.width = x + size.width
            current.height = max(current.height, size.height)
        }

        rows.append(current)
        return rows
    }

    private struct Row {
        var items: [Item] = []
        var y: CGFloat
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }
}
