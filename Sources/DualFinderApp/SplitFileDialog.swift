import SwiftUI
import DualFinderCore

struct SplitFileDialog: View {
    @ObservedObject var model: DualFinderViewModel
    let request: SplitFileDialogRequest

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            previewList
            Divider()
            footer
        }
        .frame(width: 680, height: 460)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Split File")
                    .font(.headline)
                Text(request.preview.sourceURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(request.preview.sourceURL.path)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(request.preview.chapters.count) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(request.preview.detectedEncoding)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
    }

    private var previewList: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Chapter")
                    .frame(width: 48, alignment: .trailing)
                Text("File")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Line")
                    .frame(width: 64, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(.bar)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(request.preview.chapters.enumerated()), id: \.element.id) { index, chapter in
                        row(index: index, chapter: chapter)
                        Divider()
                    }
                }
            }
        }
    }

    private func row(index: Int, chapter: TextFileSplitChapterPreview) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 48, alignment: .trailing)
            VStack(alignment: .leading, spacing: 2) {
                Text(chapter.outputFileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                    .help(chapter.outputURL.path)
                Text(chapter.heading)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(chapter.lineNumber)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var footer: some View {
        HStack {
            Text("Original file will be deleted after a successful split.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") {
                dismiss()
            }
            Button("Split") {
                model.splitFile(request.preview, on: request.side)
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(14)
    }
}
