import SwiftUI
import UniformTypeIdentifiers
import DualFinderCore

struct MergeFilesDialog: View {
    @ObservedObject var model: DualFinderViewModel
    let request: MergeFilesDialogRequest

    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool
    @State private var fileName: String
    @State private var sources: [URL]
    @State private var draggedSource: URL?

    init(model: DualFinderViewModel, request: MergeFilesDialogRequest) {
        self.model = model
        self.request = request
        _fileName = State(initialValue: request.suggestedName)
        _sources = State(initialValue: request.sources)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 14) {
                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        Text("Name")
                            .foregroundStyle(.secondary)
                            .frame(width: 72, alignment: .trailing)
                        TextField("Merged file name", text: $fileName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFocused)
                    }
                }

                sourceList

                if let validationMessage {
                    Text(validationMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            .padding(14)
            Divider()
            footer
        }
        .frame(width: 560, height: 420)
        .onAppear {
            isNameFocused = true
        }
    }

    private var header: some View {
        HStack {
            Text("Merge Files")
                .font(.headline)
            Spacer()
            Text("\(sources.count) selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
    }

    private var sourceList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(.bar)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sources.enumerated()), id: \.element) { index, source in
                        MergeFileSourceRow(index: index, source: source)
                            .opacity(draggedSource == source ? 0.55 : 1)
                            .contentShape(Rectangle())
                            .onDrag {
                                draggedSource = source
                                return NSItemProvider(object: source.path as NSString)
                            }
                            .onDrop(
                                of: [.plainText],
                                delegate: MergeFileSourceDropDelegate(
                                    target: source,
                                    sources: $sources,
                                    draggedSource: $draggedSource
                                )
                            )
                        Divider()
                    }
                }
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.24), lineWidth: 1)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Merge") {
                model.mergeFiles(sources, named: fileName, on: request.side)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
            .disabled(validationMessage != nil)
        }
        .padding(14)
    }

    private var validationMessage: String? {
        if fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Name cannot be empty."
        }
        if fileName.contains("/") || fileName.contains(":") {
            return "Name contains characters that cannot be used in a file name."
        }
        return nil
    }
}

private struct MergeFileSourceRow: View {
    let index: Int
    let source: URL

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 14)
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
            Text(source.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(source.path)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}

private struct MergeFileSourceDropDelegate: DropDelegate {
    let target: URL
    @Binding var sources: [URL]
    @Binding var draggedSource: URL?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedSource,
              draggedSource != target,
              let fromIndex = sources.firstIndex(of: draggedSource),
              let targetIndex = sources.firstIndex(of: target) else {
            return
        }

        withAnimation(.easeInOut(duration: 0.12)) {
            sources.move(
                fromOffsets: IndexSet(integer: fromIndex),
                toOffset: targetIndex > fromIndex ? targetIndex + 1 : targetIndex
            )
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedSource = nil
        return true
    }
}
