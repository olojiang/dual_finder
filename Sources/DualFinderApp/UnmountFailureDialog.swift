import SwiftUI
import DualFinderCore

struct UnmountFailureDialog: View {
    @ObservedObject var model: DualFinderViewModel
    let prompt: UnmountFailurePrompt

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Could Not Unmount \(prompt.volumeName)")
                    .font(.title2.weight(.semibold))
                Text(prompt.mountPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(prompt.failureReason)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Divider()

            Text("Processes using this volume")
                .font(.headline)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(prompt.blockers) { blocker in
                        blockerRow(blocker)
                    }
                    if prompt.blockers.isEmpty {
                        Text("No open-file processes were identified on this volume.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let inspectionError = prompt.inspectionError {
                        Text("Process inspection failed: \(inspectionError)")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack {
                Text("Force quit acts immediately. Unsaved work in that process may be lost.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Close") { model.unmountFailurePrompt = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 600, height: 620)
    }

    private func blockerRow(_ blocker: UnmountProcessBlocker) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(blocker.processName) (PID \(blocker.processID))")
                    .font(.body.weight(.semibold))
                    .textSelection(.enabled)
                if let executablePath = blocker.executablePath {
                    detail("Executable", value: executablePath)
                }
                if let userName = blocker.userName {
                    detail("User", value: userName)
                }
                ForEach(blocker.openPaths, id: \.self) { path in
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let message = prompt.terminationMessages[blocker.processID] {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(message.hasPrefix("Ended") ? .green : .secondary)
                        .textSelection(.enabled)
                }
            }

            Spacer(minLength: 4)
            terminateButton(for: blocker)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func detail(_ label: String, value: String) -> some View {
        (Text("\(label): ").foregroundColor(.secondary) + Text(value).foregroundColor(.primary))
            .font(.caption)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func terminateButton(for blocker: UnmountProcessBlocker) -> some View {
        UnmountProcessTerminateButton(model: model, blocker: blocker, message: prompt.terminationMessages[blocker.processID])
    }
}

private struct UnmountProcessTerminateButton: View {
    @ObservedObject var model: DualFinderViewModel
    let blocker: UnmountProcessBlocker
    let message: String?
    @State private var isHovered = false

    var body: some View {
        let isWorking = model.terminatingUnmountProcessIDs.contains(blocker.processID)
        let wasEnded = message?.hasPrefix("Ended") == true
        Button {
            model.forceTerminateUnmountBlocker(blocker)
        } label: {
            Image(systemName: isWorking ? "hourglass" : wasEnded ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(wasEnded ? Color.green : Color.red)
                .frame(width: 44, height: 44)
                .background(isHovered ? Color.red.opacity(0.14) : Color.clear, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isWorking || wasEnded)
        .help("Force quit \(blocker.processName) (PID \(blocker.processID)) immediately")
        .accessibilityLabel("Force quit \(blocker.processName), PID \(blocker.processID)")
        .accessibilityHint("Terminates this process immediately without confirmation.")
        .onHover { isHovered = $0 }
    }
}
