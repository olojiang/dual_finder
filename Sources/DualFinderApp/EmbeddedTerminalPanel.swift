@preconcurrency import AppKit
import SwiftUI
import DualFinderCore
import SwiftTerm

@MainActor
final class EmbeddedTerminalPaneModel: ObservableObject {
    static let minimumHeight: CGFloat = 140
    static let maximumHeight: CGFloat = 420
    static let minimumSplitFraction = 0.18
    static let maximumSplitFraction = 0.82

    @Published var isExpanded = false
    @Published var isMaximized = false
    @Published var height: CGFloat = 220
    @Published var tabs: [EmbeddedTerminalTabModel] = []
    @Published var selectedTabID: UUID?
    @Published var layout: EmbeddedTerminalLayout?

    func toggle(currentDirectory: URL) {
        if isExpanded {
            isExpanded = false
            isMaximized = false
        } else {
            ensureTab(currentDirectory: currentDirectory)
            isExpanded = true
        }
    }

    func collapse() {
        isExpanded = false
        isMaximized = false
    }

    func resize(by delta: CGFloat) {
        guard !isMaximized else { return }
        resize(to: height - delta)
    }

    func resize(to height: CGFloat) {
        guard !isMaximized else { return }
        self.height = Self.clampedHeight(height)
    }

    static func clampedHeight(_ height: CGFloat) -> CGFloat {
        min(max(height, minimumHeight), maximumHeight)
    }

    func addTab(currentDirectory: URL) {
        let tab = makeTab(currentDirectory: currentDirectory)
        tabs.append(tab)
        selectedTabID = tab.id
        if let layout {
            self.layout = layout.replacingLeaf(selectedLeafID(in: layout), with: .leaf(tab.id))
        } else {
            layout = .leaf(tab.id)
        }
    }

    func selectTab(_ id: UUID) {
        selectedTabID = id
        guard let layout, !layout.containsLeaf(id) else { return }
        self.layout = layout.replacingLeaf(selectedLeafID(in: layout), with: .leaf(id))
    }

    @discardableResult
    func selectTab(atZeroBasedIndex index: Int, focus: Bool = false) -> EmbeddedTerminalTabModel? {
        guard tabs.indices.contains(index) else { return nil }
        let tab = tabs[index]
        selectTab(tab.id)
        if focus {
            DispatchQueue.main.async {
                tab.focus()
            }
        }
        return tab
    }

    func toggleMaximized(currentDirectory: URL) {
        ensureTab(currentDirectory: currentDirectory)
        isExpanded = true
        isMaximized.toggle()
    }

    func closeTab(_ id: UUID) {
        tabs.first(where: { $0.id == id })?.stop()
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if tabs.isEmpty {
            selectedTabID = nil
            layout = nil
            isExpanded = false
            isMaximized = false
        } else if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
        }
        layout = layout?.removingLeaf(id)
        if layout == nil, let selectedTabID {
            layout = .leaf(selectedTabID)
        }
    }

    func splitSelected(direction: EmbeddedTerminalSplitDirection, currentDirectory: URL) {
        ensureTab(currentDirectory: currentDirectory)
        guard let selectedTabID else { return }
        split(tabID: selectedTabID, direction: direction, currentDirectory: currentDirectory)
    }

    func split(tabID: UUID, direction: EmbeddedTerminalSplitDirection, currentDirectory: URL) {
        guard tabs.contains(where: { $0.id == tabID }) else { return }
        let newTab = makeTab(currentDirectory: currentDirectory)
        tabs.append(newTab)
        let replacement = EmbeddedTerminalLayout.split(
            id: UUID(),
            direction: direction,
            fraction: 0.5,
            first: .leaf(tabID),
            second: .leaf(newTab.id)
        )
        layout = (layout ?? .leaf(tabID)).replacingLeaf(tabID, with: replacement)
        self.selectedTabID = newTab.id
    }

    func resizeSplit(id: UUID, by delta: CGFloat, availableLength: CGFloat) {
        guard availableLength > 0, let layout else { return }
        let ratioDelta = Double(delta / availableLength)
        self.layout = layout.updatingSplit(id: id) { fraction in
            Self.clampedSplitFraction(fraction + ratioDelta)
        }
    }

    func resizeSplit(id: UUID, to fraction: Double) {
        guard let layout else { return }
        self.layout = layout.updatingSplit(id: id) { _ in
            Self.clampedSplitFraction(fraction)
        }
    }

    func tab(with id: UUID) -> EmbeddedTerminalTabModel? {
        tabs.first(where: { $0.id == id })
    }

    func tabID(containing view: NSView) -> UUID? {
        tabs.first { tab in
            view === tab.terminalView || view.isDescendant(of: tab.terminalView)
        }?.id
    }

    @discardableResult
    func closeTab(containing view: NSView) -> Bool {
        guard let id = tabID(containing: view) else { return false }
        closeTab(id)
        return true
    }

    @discardableResult
    func focusAdjacentTab(from id: UUID, direction: EmbeddedTerminalFocusDirection) -> Bool {
        guard let adjacentID = layout?.adjacentLeaf(to: id, direction: direction),
              let tab = tab(with: adjacentID) else {
            return false
        }
        selectTab(adjacentID)
        DispatchQueue.main.async {
            tab.focus()
        }
        return true
    }

    static func clampedSplitFraction(_ fraction: Double) -> Double {
        min(max(fraction, minimumSplitFraction), maximumSplitFraction)
    }

    private func makeTab(currentDirectory: URL) -> EmbeddedTerminalTabModel {
        let tab = EmbeddedTerminalTabModel(workingDirectory: currentDirectory)
        tab.onProcessTerminated = { [weak self] tab in
            self?.closeTab(tab.id)
        }
        return tab
    }

    private func ensureTab(currentDirectory: URL) {
        guard tabs.isEmpty else {
            selectedTabID = selectedTabID ?? tabs.first?.id
            layout = layout ?? selectedTabID.map { .leaf($0) }
            return
        }
        addTab(currentDirectory: currentDirectory)
    }

    private func selectedLeafID(in layout: EmbeddedTerminalLayout) -> UUID {
        if let selectedTabID, layout.containsLeaf(selectedTabID) {
            return selectedTabID
        }
        return layout.firstLeafID ?? tabs.first?.id ?? UUID()
    }
}

enum EmbeddedTerminalSplitDirection: Equatable {
    case sideBySide
    case stacked
}

enum EmbeddedTerminalFocusDirection: Equatable {
    case left
    case right
    case up
    case down

    static func commandArrowDirection(for event: NSEvent) -> EmbeddedTerminalFocusDirection? {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags == [.command] else { return nil }

        switch event.keyCode {
        case 123:
            return .left
        case 124:
            return .right
        case 126:
            return .up
        case 125:
            return .down
        default:
            return nil
        }
    }
}

indirect enum EmbeddedTerminalLayout: Equatable {
    case leaf(UUID)
    case split(
        id: UUID,
        direction: EmbeddedTerminalSplitDirection,
        fraction: Double,
        first: EmbeddedTerminalLayout,
        second: EmbeddedTerminalLayout
    )

    var firstLeafID: UUID? {
        switch self {
        case .leaf(let id):
            return id
        case .split(_, _, _, let first, let second):
            return first.firstLeafID ?? second.firstLeafID
        }
    }

    func containsLeaf(_ id: UUID) -> Bool {
        switch self {
        case .leaf(let leafID):
            return leafID == id
        case .split(_, _, _, let first, let second):
            return first.containsLeaf(id) || second.containsLeaf(id)
        }
    }

    func replacingLeaf(_ targetID: UUID, with replacement: EmbeddedTerminalLayout) -> EmbeddedTerminalLayout {
        switch self {
        case .leaf(let id):
            return id == targetID ? replacement : self
        case .split(let id, let direction, let fraction, let first, let second):
            return .split(
                id: id,
                direction: direction,
                fraction: fraction,
                first: first.replacingLeaf(targetID, with: replacement),
                second: second.replacingLeaf(targetID, with: replacement)
            )
        }
    }

    func removingLeaf(_ targetID: UUID) -> EmbeddedTerminalLayout? {
        switch self {
        case .leaf(let id):
            return id == targetID ? nil : self
        case .split(let id, let direction, let fraction, let first, let second):
            let newFirst = first.removingLeaf(targetID)
            let newSecond = second.removingLeaf(targetID)
            switch (newFirst, newSecond) {
            case let (first?, second?):
                return .split(id: id, direction: direction, fraction: fraction, first: first, second: second)
            case let (first?, nil):
                return first
            case let (nil, second?):
                return second
            case (nil, nil):
                return nil
            }
        }
    }

    func updatingSplit(id targetID: UUID, update: (Double) -> Double) -> EmbeddedTerminalLayout {
        switch self {
        case .leaf:
            return self
        case .split(let id, let direction, let fraction, let first, let second):
            return .split(
                id: id,
                direction: direction,
                fraction: id == targetID ? update(fraction) : fraction,
                first: first.updatingSplit(id: targetID, update: update),
                second: second.updatingSplit(id: targetID, update: update)
            )
        }
    }

    func adjacentLeaf(to targetID: UUID, direction: EmbeddedTerminalFocusDirection) -> UUID? {
        switch self {
        case .leaf:
            return nil
        case .split(_, let splitDirection, _, let first, let second):
            if first.containsLeaf(targetID) {
                if let nested = first.adjacentLeaf(to: targetID, direction: direction) {
                    return nested
                }
                switch (splitDirection, direction) {
                case (.sideBySide, .right):
                    return second.boundaryLeaf(facing: .left)
                case (.stacked, .down):
                    return second.boundaryLeaf(facing: .up)
                default:
                    return nil
                }
            }

            if second.containsLeaf(targetID) {
                if let nested = second.adjacentLeaf(to: targetID, direction: direction) {
                    return nested
                }
                switch (splitDirection, direction) {
                case (.sideBySide, .left):
                    return first.boundaryLeaf(facing: .right)
                case (.stacked, .up):
                    return first.boundaryLeaf(facing: .down)
                default:
                    return nil
                }
            }

            return nil
        }
    }

    private func boundaryLeaf(facing direction: EmbeddedTerminalFocusDirection) -> UUID? {
        switch self {
        case .leaf(let id):
            return id
        case .split(_, let splitDirection, _, let first, let second):
            switch (splitDirection, direction) {
            case (.sideBySide, .left):
                return first.boundaryLeaf(facing: direction)
            case (.sideBySide, .right):
                return second.boundaryLeaf(facing: direction)
            case (.stacked, .up):
                return first.boundaryLeaf(facing: direction)
            case (.stacked, .down):
                return second.boundaryLeaf(facing: direction)
            default:
                return first.firstLeafID ?? second.firstLeafID
            }
        }
    }
}

@MainActor
final class EmbeddedTerminalTabModel: ObservableObject, Identifiable {
    let id = UUID()
    @Published var title: String
    @Published var workingDirectory: URL
    @Published private(set) var isRunning = false

    let terminalView: LocalProcessTerminalView
    var onProcessTerminated: ((EmbeddedTerminalTabModel) -> Void)?
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

    func handleWorkingDirectoryUpdate(_ directory: String?) {
        guard let directory, !directory.isEmpty else { return }
        let url = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        workingDirectory = url
        title = Self.title(for: url)
    }

    func handleTerminalTitle(_ title: String) {
        self.title = Self.title(for: workingDirectory)
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
            self.handleTerminalTitle(title)
        }
    }

    nonisolated func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        Task { @MainActor [weak self] in
            self?.handleWorkingDirectoryUpdate(directory)
        }
    }

    nonisolated func processTerminated(source: TerminalView, exitCode: Int32?) {
        Task { @MainActor [weak self] in
            self?.handleProcessTerminated(exitCode: exitCode)
        }
    }
}

extension EmbeddedTerminalTabModel {
    func handleProcessTerminated(exitCode: Int32?) {
        isRunning = false
        if let onProcessTerminated {
            onProcessTerminated(self)
            return
        }

        let status = exitCode.map { String($0) } ?? "unknown"
        terminalView.feed(text: "\n[process exited: \(status)]\n")
    }
}

struct EmbeddedTerminalPanel: View {
    let side: PaneSide
    @ObservedObject var paneModel: EmbeddedTerminalPaneModel
    let currentDirectory: URL
    let openExternal: (URL) -> Void
    let toggleMaximized: () -> Void

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
            if let layout = paneModel.layout {
                EmbeddedTerminalLayoutView(
                    layout: layout,
                    paneModel: paneModel,
                    currentDirectory: currentDirectory
                )
            } else if let selectedTab {
                EmbeddedTerminalTabView(
                    tab: selectedTab,
                    isSelected: selectedTab.id == paneModel.selectedTabID,
                    select: {
                        paneModel.selectTab(selectedTab.id)
                    }
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .background(EmbeddedTerminalShortcutHandler(
            focusedTabID: { window in
                focusedTerminalTabID(in: window)
            },
            splitSideBySide: {
                splitFocusedTerminal(direction: .sideBySide)
            },
            splitStacked: {
                splitFocusedTerminal(direction: .stacked)
            }
        ))
    }

    private func splitFocusedTerminal(direction: EmbeddedTerminalSplitDirection) {
        if let focusedTabID = focusedTerminalTabID(in: NSApp.keyWindow) {
            paneModel.split(tabID: focusedTabID, direction: direction, currentDirectory: currentDirectory)
        } else {
            paneModel.splitSelected(direction: direction, currentDirectory: currentDirectory)
        }
    }

    private func focusedTerminalTabID(in window: NSWindow?) -> UUID? {
        guard let firstResponder = window?.firstResponder as? NSView else { return nil }
        return paneModel.tabs.first { tab in
            firstResponder === tab.terminalView || firstResponder.isDescendant(of: tab.terminalView)
        }?.id
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
            Button {
                paneModel.splitSelected(direction: .sideBySide, currentDirectory: currentDirectory)
            } label: {
                Image(systemName: "rectangle.split.2x1")
            }
            .buttonStyle(.borderless)
            .help("Split terminal right (Command-D)")
            Button {
                paneModel.splitSelected(direction: .stacked, currentDirectory: currentDirectory)
            } label: {
                Image(systemName: "rectangle.split.1x2")
            }
            .buttonStyle(.borderless)
            .help("Split terminal down (Command-Shift-D)")
            Button {
                toggleMaximized()
            } label: {
                Image(systemName: paneModel.isMaximized ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            }
            .buttonStyle(.borderless)
            .help(paneModel.isMaximized ? "Restore terminal" : "Maximize terminal")
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
                paneModel.selectTab(tab.id)
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

private struct EmbeddedTerminalLayoutView: View {
    let layout: EmbeddedTerminalLayout
    @ObservedObject var paneModel: EmbeddedTerminalPaneModel
    let currentDirectory: URL

    @State private var activeResizeSplitID: UUID?
    @State private var dragStartFraction: Double?
    @State private var dragStartAvailableLength: CGFloat = 0
    @State private var dragAccumulatedDelta: CGFloat = 0
    @State private var dragPreviewFraction: Double?

    var body: some View {
        GeometryReader { geometry in
            content(for: layout, size: geometry.size)
        }
    }

    private func content(for layout: EmbeddedTerminalLayout, size: CGSize) -> AnyView {
        switch layout {
        case .leaf(let tabID):
            if let tab = paneModel.tab(with: tabID) {
                return AnyView(EmbeddedTerminalTabView(
                    tab: tab,
                    isSelected: paneModel.selectedTabID == tabID,
                    select: {
                        paneModel.selectTab(tabID)
                    }
                ))
            } else {
                return AnyView(Color.clear)
            }
        case .split(let id, let direction, let fraction, let first, let second):
            switch direction {
            case .sideBySide:
                let availableWidth = max(size.width - 5, 1)
                return AnyView(ZStack(alignment: .leading) {
                    HStack(spacing: 0) {
                        content(for: first, size: CGSize(width: availableWidth * fraction, height: size.height))
                            .frame(width: availableWidth * fraction)
                        splitResizeHandle(id: id, fraction: fraction, availableLength: availableWidth, axis: .vertical)
                        content(for: second, size: CGSize(width: availableWidth * (1 - fraction), height: size.height))
                            .frame(width: availableWidth * (1 - fraction))
                    }
                    splitPreviewLine(id: id, direction: direction, availableLength: availableWidth)
                })
            case .stacked:
                let availableHeight = max(size.height - 5, 1)
                return AnyView(ZStack(alignment: .top) {
                    VStack(spacing: 0) {
                        content(for: first, size: CGSize(width: size.width, height: availableHeight * fraction))
                            .frame(height: availableHeight * fraction)
                        splitResizeHandle(id: id, fraction: fraction, availableLength: availableHeight, axis: .horizontal)
                        content(for: second, size: CGSize(width: size.width, height: availableHeight * (1 - fraction)))
                            .frame(height: availableHeight * (1 - fraction))
                    }
                    splitPreviewLine(id: id, direction: direction, availableLength: availableHeight)
                })
            }
        }
    }

    private func splitResizeHandle(
        id: UUID,
        fraction: Double,
        availableLength: CGFloat,
        axis: LayoutResizeHandle.Axis
    ) -> some View {
        LayoutResizeHandle(
            axis: axis,
            length: nil,
            onDrag: { delta in
                beginSplitDragIfNeeded(id: id, fraction: fraction, availableLength: availableLength)
                dragAccumulatedDelta += delta
                let nextFraction = (dragStartFraction ?? fraction)
                    + Double(dragAccumulatedDelta / max(dragStartAvailableLength, 1))
                dragPreviewFraction = EmbeddedTerminalPaneModel.clampedSplitFraction(nextFraction)
            },
            onDragEnded: {
                if activeResizeSplitID == id, let dragPreviewFraction {
                    paneModel.resizeSplit(id: id, to: dragPreviewFraction)
                }
                resetSplitDrag()
            }
        )
    }

    @ViewBuilder
    private func splitPreviewLine(
        id: UUID,
        direction: EmbeddedTerminalSplitDirection,
        availableLength: CGFloat
    ) -> some View {
        if activeResizeSplitID == id, let dragPreviewFraction {
            let offset = availableLength * dragPreviewFraction + 2.5
            switch direction {
            case .sideBySide:
                Rectangle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(width: 1)
                    .offset(x: offset)
                    .allowsHitTesting(false)
            case .stacked:
                Rectangle()
                    .fill(Color.accentColor.opacity(0.85))
                    .frame(height: 1)
                    .offset(y: offset)
                    .allowsHitTesting(false)
            }
        }
    }

    private func beginSplitDragIfNeeded(id: UUID, fraction: Double, availableLength: CGFloat) {
        guard activeResizeSplitID == nil else { return }
        activeResizeSplitID = id
        dragStartFraction = fraction
        dragStartAvailableLength = max(availableLength, 1)
        dragAccumulatedDelta = 0
    }

    private func resetSplitDrag() {
        activeResizeSplitID = nil
        dragStartFraction = nil
        dragStartAvailableLength = 0
        dragAccumulatedDelta = 0
        dragPreviewFraction = nil
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
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        EmbeddedLocalTerminalView(tab: tab)
            .background(Color(nsColor: tab.terminalView.nativeBackgroundColor))
            .onTapGesture {
                select()
                tab.focus()
            }
        .onAppear {
            tab.startIfNeeded()
            if isSelected {
                DispatchQueue.main.async {
                    tab.focus()
                }
            }
        }
    }
}

private struct EmbeddedTerminalShortcutHandler: NSViewRepresentable {
    let focusedTabID: (NSWindow?) -> UUID?
    let splitSideBySide: () -> Void
    let splitStacked: () -> Void

    func makeNSView(context: Context) -> NSView {
        context.coordinator.install()
        return NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.focusedTabID = focusedTabID
        context.coordinator.splitSideBySide = splitSideBySide
        context.coordinator.splitStacked = splitStacked
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            focusedTabID: focusedTabID,
            splitSideBySide: splitSideBySide,
            splitStacked: splitStacked
        )
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator {
        var focusedTabID: (NSWindow?) -> UUID?
        var splitSideBySide: () -> Void
        var splitStacked: () -> Void
        private var monitor: Any?

        init(
            focusedTabID: @escaping (NSWindow?) -> UUID?,
            splitSideBySide: @escaping () -> Void,
            splitStacked: @escaping () -> Void
        ) {
            self.focusedTabID = focusedTabID
            self.splitSideBySide = splitSideBySide
            self.splitStacked = splitStacked
        }

        func install() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) == true ? nil : event
            }
        }

        func uninstall() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func handle(_ event: NSEvent) -> Bool {
            guard event.charactersIgnoringModifiers?.lowercased() == "d",
                  event.modifierFlags.contains(.command),
                  !event.modifierFlags.contains(.option),
                  !event.modifierFlags.contains(.control),
                  focusedTabID(event.window) != nil
            else {
                return false
            }

            if event.modifierFlags.contains(.shift) {
                splitStacked()
            } else {
                splitSideBySide()
            }
            return true
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
