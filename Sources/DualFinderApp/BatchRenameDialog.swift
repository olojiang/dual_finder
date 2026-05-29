import SwiftUI
import AppKit
import DualFinderCore

private enum BatchRenameDialogMode: String, CaseIterable, Identifiable {
    case numbering = "Number"
    case replace = "Replace"
    case regex = "Regex"
    case extensionChange = "Extension"
    case metadata = "Metadata"

    var id: Self { self }
}

struct BatchRenameDialog: View {
    @ObservedObject var model: DualFinderViewModel
    let side: PaneSide

    @Environment(\.dismiss) private var dismiss
    @State private var mode: BatchRenameDialogMode = .numbering
    @State private var prefix = "File "
    @State private var suffix = ""
    @State private var startNumber = 1
    @State private var padding = 2
    @State private var includeOriginalName = false
    @State private var search = ""
    @State private var replacement = ""
    @State private var caseSensitive = true
    @State private var regexPattern = ""
    @State private var regexReplacement = ""
    @State private var newExtension = ""
    @State private var metadataTemplate = "{modifiedDate}_{modifiedTime}_{base}{extWithDot}"
    @State private var isExpanded = false

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
                    labeledTextField("Find", text: $search)
                    labeledTextField("Replace", text: $replacement)
                    GridRow {
                        Text("")
                        Toggle("Case sensitive", isOn: $caseSensitive)
                    }
                }
            case .regex:
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    labeledTextField("Pattern", text: $regexPattern)
                    labeledTextField("Replace", text: $regexReplacement)
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
                dismiss()
            }
            Button("Rename") {
                if case let .success(previews) = previewResult {
                    model.applyBatchRename(previews, on: side)
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(!canApply)
        }
        .padding(14)
    }

    private var previewResult: Result<[BatchRenamePreview], Error> {
        Result {
            try model.batchRenamePreviews(rule: rule, on: side)
        }
    }

    private var canApply: Bool {
        guard case let .success(previews) = previewResult else { return false }
        return previews.contains(where: \.isChanged) && previews.allSatisfy { $0.status.allowsApply }
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
            return .literalReplace(search: search, replacement: replacement, caseSensitive: caseSensitive)
        case .regex:
            return .regularExpression(pattern: regexPattern, replacement: regexReplacement)
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
}
