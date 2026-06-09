import AppKit
import SwiftUI
import DualFinderCore
import SwiftTerm

@MainActor
final class EmbeddedTerminalPaneModel: ObservableObject {
    @Published var isExpanded = false
    @Published var height: CGFloat = 220
    @Published var tabs: [EmbeddedTerminalTabModel] = []
    @Published var selectedTabID: UUID?

    func toggle(currentDirectory: URL) {
        if isExpanded {
            isExpanded = false
        } else {
            ensureTab(currentDirectory: currentDirectory)
            isExpanded = true
        }
    }

    func collapse() {
        isExpanded = false
    }

    func resize(by delta: CGFloat) {
        height = min(max(height - delta, 140), 420)
    }

    func addTab(currentDirectory: URL) {
        let tab = EmbeddedTerminalTabModel(workingDirectory: currentDirectory)
        tabs.append(tab)
        selectedTabID = tab.id
    }

    func closeTab(_ id: UUID) {
        tabs.first(where: { $0.id == id })?.stop()
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            selectedTabID = nil
            isExpanded = false
        } else if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
    }

    private func ensureTab(currentDirectory: URL) {
        guard tabs.isEmpty else {
            selectedTabID = selectedTabID ?? tabs.first?.id
            return
        }
        addTab(currentDirectory: currentDirectory)
    }
}

@MainActor
final class EmbeddedTerminalTabModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var workingDirectory: URL
    @Published private(set) var isRunning = false

    let terminalView: LocalProcessTerminalView
    private var hasStarted = false

    init(workingDirectory: URL) {
        self.workingDirectory = workingDirectory
        self.title = Self.title(for: workingDirectory)
        self.terminalView = LocalProcessTerminalView(frame: .zero)
        configureTerminalView()
    }

    func startIfNeeded() {
        guard !hasStarted else { return }
        hasStarted = true
        isRunning = true

        let shell = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let executable = FileManager.default.fileExists(atPath: shell) ? shell : "/bin/zsh"
        let shellName = URL(fileURLWithPath: executable).lastPathComponent
        terminalView.feed(text: "Dual Finder Terminal\n\(workingDirectory.path)\n\n")
        terminalView.startProcess(
            executable: executable,
            execName: "-\(shellName)",
            currentDirectory: workingDirectory.path
        )
    }

    func stop() {
        guard isRunning else { return }
        terminalView.terminate()
    }

    func focus() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    private func configureTerminalView() {
        terminalView.processDelegate = self
        terminalView.autoresizingMask = [.width, .height]
        terminalView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        terminalView.nativeForegroundColor = NSColor(calibratedWhite: 0.88, alpha: 1)
        terminalView.nativeBackgroundColor = NSColor(calibratedWhite: 0.07, alpha: 1)
        terminalView.caretColor = .systemGreen
        terminalView.layer?.backgroundColor = terminalView.nativeBackgroundColor.cgColor
        terminalView.caretViewTracksFocus = true
    }

    private func updateWorkingDirectory(_ directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let previousAutomaticTitle = Self.title(for: workingDirectory)
        let url = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        workingDirectory = url
        if title == previousAutomaticTitle || title.isEmpty {
            title = Self.title(for: url)
        }
    }

    private static func title(for directory: URL) -> String {
        let name = directory.lastPathComponent
        return name.isEmpty ? directory.path : name
    }
}

extension EmbeddedTerminalTabModel: LocalProcessTerminalViewDelegate {
    nonisolated func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    nonisolated func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.title = title.isEmpty ? Self.title(for: self.workingDirectory) : title
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            self?.updateWorkingDirectory(directory)
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.isRunning = false
            let status = exitCode.map { String($0) } ?? "unknown"
            self.terminalView.feed(text: "\n[process exited: \(status)]\n")
        }
    }
}

struct EmbeddedTerminalPanel: View {
    let side: PaneSide
    @ObservedObject var paneModel: EmbeddedTerminalPaneModel
    let currentDirectory: URL
    let openExternal: (URL) -> Void

    private var selectedTab: EmbeddedTerminalTabModel? {
        if let selectedTabID = paneModel.selectedTabID,
           let tab = paneModel.tabs.first(where: { $0.id == selectedTabID }) {
            return tab
        }
        return paneModel.tabs.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let selectedTab {
                EmbeddedTerminalTabView(tab: selectedTab)
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "terminal")
                .foregroundStyle(.secondary)
            Text(side == .left ? "Left Terminal" : "Right Terminal")
                .font(.caption.weight(.semibold))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(paneModel.tabs) { tab in
                        terminalTabButton(tab)
                    }
                }
            }
            Button {
                paneModel.addTab(currentDirectory: currentDirectory)
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New terminal tab")
            if let selectedTab {
                EmbeddedTerminalHeaderControls(
                    tab: selectedTab,
                    openExternal: openExternal
                )
            }
            Button {
                paneModel.collapse()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Collapse terminal")
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
        .background(.bar)
    }

    private func terminalTabButton(_ tab: EmbeddedTerminalTabModel) -> some View {
        HStack(spacing: 4) {
            Button {
                paneModel.selectedTabID = tab.id
            } label: {
                HStack(spacing: 4) {
                    Circle()
                        .fill(tab.isRunning ? Color.green : Color.secondary.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(tab.title)
                        .lineLimit(1)
                }
                .frame(maxWidth: 120)
            }
            .buttonStyle(.plain)
            .help(tab.workingDirectory.path)
            Button {
                paneModel.closeTab(tab.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Close terminal tab")
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tab.id == paneModel.selectedTabID ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(tab.title) terminal tab")
    }
}

private struct EmbeddedTerminalHeaderControls: View {
    @ObservedObject var tab: EmbeddedTerminalTabModel
    let openExternal: (URL) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if tab.isRunning {
                Button {
                    tab.stop()
                } label: {
                    Image(systemName: "stop.fill")
                }
                .buttonStyle(.borderless)
                .help("Terminate terminal session")
            }
            Button {
                openExternal(tab.workingDirectory)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Open this directory in Ghostty or Terminal")
        }
    }
}

private struct EmbeddedTerminalTabView: View {
    @ObservedObject var tab: EmbeddedTerminalTabModel

    var body: some View {
        EmbeddedLocalTerminalView(tab: tab)
            .background(Color(nsColor: tab.terminalView.nativeBackgroundColor))
            .onTapGesture {
                tab.focus()
            }
        .onAppear {
            tab.startIfNeeded()
            DispatchQueue.main.async {
                tab.focus()
            }
        }
    }
}

private struct EmbeddedLocalTerminalView: NSViewRepresentable {
    @ObservedObject var tab: EmbeddedTerminalTabModel

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        tab.terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        nsView.processDelegate = tab
        tab.startIfNeeded()
    }
}
