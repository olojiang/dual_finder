import Foundation
import AppKit
import Testing
@testable import DualFinderApp

@MainActor
@Suite("EmbeddedTerminalPaneModel")
struct EmbeddedTerminalPaneModelTests {
    @Test("defaults collapsed and creates first tab on expand")
    func defaultsCollapsedAndCreatesFirstTab() {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        #expect(!model.isExpanded)
        #expect(model.tabs.isEmpty)

        model.toggle(currentDirectory: directory)

        #expect(model.isExpanded)
        #expect(model.tabs.count == 1)
        #expect(model.tabs.first?.workingDirectory.path == "/tmp")
        #expect(model.selectedTabID == model.tabs.first?.id)
    }

    @Test("closing the last tab collapses the panel")
    func closingLastTabCollapsesPanel() throws {
        let model = EmbeddedTerminalPaneModel()
        model.toggle(currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true))
        let tabID = try #require(model.tabs.first?.id)

        model.closeTab(tabID)

        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
        #expect(!model.isExpanded)
    }

    @Test("process exit closes the matching terminal")
    func processExitClosesMatchingTerminal() throws {
        let model = EmbeddedTerminalPaneModel()
        model.toggle(currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true))
        let tab = try #require(model.tabs.first)

        tab.handleProcessTerminated(exitCode: 0)

        #expect(model.tabs.isEmpty)
        #expect(model.selectedTabID == nil)
        #expect(model.layout == nil)
        #expect(!model.isExpanded)
    }

    @Test("process exit removes only its split leaf")
    func processExitRemovesOnlyItsSplitLeaf() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        let firstTab = try #require(model.tabs.first)
        model.splitSelected(direction: .sideBySide, currentDirectory: directory)
        let remainingTabID = try #require(model.selectedTabID)

        firstTab.handleProcessTerminated(exitCode: 0)

        #expect(model.tabs.map(\.id) == [remainingTabID])
        #expect(model.selectedTabID == remainingTabID)
        #expect(model.layout == .leaf(remainingTabID))
        #expect(model.isExpanded)
    }

    @Test("focused terminal descendant can be closed")
    func focusedTerminalDescendantCanBeClosed() throws {
        let model = EmbeddedTerminalPaneModel()
        model.toggle(currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true))
        let tab = try #require(model.tabs.first)
        let nestedView = NSView(frame: .zero)
        tab.terminalView.addSubview(nestedView)

        let didClose = model.closeTab(containing: nestedView)

        #expect(didClose)
        #expect(model.tabs.isEmpty)
    }

    @Test("height resize is clamped")
    func heightResizeIsClamped() {
        let model = EmbeddedTerminalPaneModel()

        model.resize(by: 1_000)
        #expect(model.height == 140)

        model.resize(by: -1_000)
        #expect(model.height == 420)
    }

    @Test("maximize creates a tab and toggles restore state")
    func maximizeCreatesTabAndTogglesRestoreState() {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggleMaximized(currentDirectory: directory)

        #expect(model.isExpanded)
        #expect(model.isMaximized)
        #expect(model.tabs.count == 1)
        #expect(model.tabs.first?.workingDirectory.path == "/tmp")

        model.toggleMaximized(currentDirectory: directory)

        #expect(model.isExpanded)
        #expect(!model.isMaximized)
    }

    @Test("collapse and last tab close leave terminal restored")
    func collapseAndLastTabCloseLeaveTerminalRestored() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggleMaximized(currentDirectory: directory)
        model.collapse()

        #expect(!model.isExpanded)
        #expect(!model.isMaximized)

        model.toggleMaximized(currentDirectory: directory)
        let tabID = try #require(model.tabs.first?.id)
        model.closeTab(tabID)

        #expect(!model.isExpanded)
        #expect(!model.isMaximized)
    }

    @Test("resize is ignored while maximized")
    func resizeIsIgnoredWhileMaximized() {
        let model = EmbeddedTerminalPaneModel()
        model.toggleMaximized(currentDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true))

        model.resize(by: -1_000)

        #expect(model.height == 220)
    }

    @Test("splitting selected terminal creates a second pane")
    func splittingSelectedTerminalCreatesSecondPane() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        let originalTabID = try #require(model.selectedTabID)

        model.splitSelected(direction: .sideBySide, currentDirectory: directory)

        #expect(model.tabs.count == 2)
        #expect(model.selectedTabID != originalTabID)
        guard case .split(_, .sideBySide, 0.5, .leaf(originalTabID), .leaf(let newTabID)) = model.layout else {
            Issue.record("Expected a side-by-side split layout")
            return
        }
        #expect(model.selectedTabID == newTabID)
    }

    @Test("splitting an explicit terminal ignores stale selected tab")
    func splittingExplicitTerminalIgnoresStaleSelectedTab() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        let firstTabID = try #require(model.selectedTabID)
        model.splitSelected(direction: .stacked, currentDirectory: directory)
        let secondTabID = try #require(model.selectedTabID)

        model.split(tabID: firstTabID, direction: .sideBySide, currentDirectory: directory)

        #expect(model.tabs.count == 3)
        #expect(model.selectedTabID != secondTabID)
        guard case .split(_, .stacked, _, .split(_, .sideBySide, _, .leaf(firstTabID), .leaf), .leaf(secondTabID)) = model.layout else {
            Issue.record("Expected the focused first terminal leaf to be split, not the stale selected tab")
            return
        }
    }

    @Test("split resizing is clamped")
    func splitResizingIsClamped() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        model.splitSelected(direction: .stacked, currentDirectory: directory)
        guard case .split(let splitID, _, _, _, _) = model.layout else {
            Issue.record("Expected a split layout")
            return
        }

        model.resizeSplit(id: splitID, by: 1_000, availableLength: 1_000)
        guard case .split(_, _, let lowFraction, _, _) = model.layout else {
            Issue.record("Expected a split layout after resize")
            return
        }
        #expect(lowFraction == 0.18)

        model.resizeSplit(id: splitID, by: -1_000, availableLength: 1_000)
        guard case .split(_, _, let highFraction, _, _) = model.layout else {
            Issue.record("Expected a split layout after resize")
            return
        }
        #expect(highFraction == 0.82)
    }

    @Test("split drag deltas match visual divider movement")
    func splitDragDeltasMatchVisualDividerMovement() {
        let sideBySideDelta = EmbeddedTerminalPaneModel.splitFractionDelta(
            for: .sideBySide,
            dragDelta: 100,
            availableLength: 1_000
        )
        let stackedDelta = EmbeddedTerminalPaneModel.splitFractionDelta(
            for: .stacked,
            dragDelta: 100,
            availableLength: 1_000
        )

        #expect(abs(sideBySideDelta - 0.1) < 0.0001)
        #expect(abs(stackedDelta + 0.1) < 0.0001)
    }

    @Test("terminal split focus moves by direction")
    func terminalSplitFocusMovesByDirection() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        let leftTabID = try #require(model.selectedTabID)
        model.splitSelected(direction: .sideBySide, currentDirectory: directory)
        let rightTabID = try #require(model.selectedTabID)

        #expect(model.focusAdjacentTab(from: rightTabID, direction: .left))
        #expect(model.selectedTabID == leftTabID)
        #expect(model.focusAdjacentTab(from: leftTabID, direction: .right))
        #expect(model.selectedTabID == rightTabID)
    }

    @Test("terminal stacked split focus moves vertically")
    func terminalStackedSplitFocusMovesVertically() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        let topTabID = try #require(model.selectedTabID)
        model.splitSelected(direction: .stacked, currentDirectory: directory)
        let bottomTabID = try #require(model.selectedTabID)

        #expect(model.focusAdjacentTab(from: bottomTabID, direction: .up))
        #expect(model.selectedTabID == topTabID)
        #expect(model.focusAdjacentTab(from: topTabID, direction: .down))
        #expect(model.selectedTabID == bottomTabID)
    }

    @Test("terminal tab index selection focuses requested tab")
    func terminalTabIndexSelectionFocusesRequestedTab() throws {
        let model = EmbeddedTerminalPaneModel()
        let directory = URL(fileURLWithPath: "/tmp", isDirectory: true)

        model.toggle(currentDirectory: directory)
        model.addTab(currentDirectory: directory.appendingPathComponent("second", isDirectory: true))
        model.addTab(currentDirectory: directory.appendingPathComponent("third", isDirectory: true))

        let selected = try #require(model.selectTab(atZeroBasedIndex: 1))

        #expect(selected.workingDirectory.lastPathComponent == "second")
        #expect(model.selectedTabID == selected.id)
    }

    @Test("terminal tab title follows working directory basename")
    func terminalTabTitleFollowsWorkingDirectoryBasename() {
        let tab = EmbeddedTerminalTabModel(
            workingDirectory: URL(fileURLWithPath: "/Users/hunter/Workspace/dual_finder", isDirectory: true)
        )

        #expect(tab.title == "dual_finder")

        tab.handleTerminalTitle("hunter@host:~/Workspace/dual_finder")
        #expect(tab.title == "dual_finder")

        tab.handleWorkingDirectoryUpdate("/Users/hunter")
        #expect(tab.title == "hunter")
    }

    @Test("terminal working directory update accepts file URLs and paths")
    func terminalWorkingDirectoryUpdateAcceptsFileURLsAndPaths() throws {
        let fileURL = try #require(EmbeddedTerminalTabModel.workingDirectoryURL(from: "file:///Users/hunter/Workspace"))
        let pathURL = try #require(EmbeddedTerminalTabModel.workingDirectoryURL(from: "/Users/hunter/Workspace"))

        #expect(fileURL.path == "/Users/hunter/Workspace")
        #expect(pathURL.path == "/Users/hunter/Workspace")
        #expect(EmbeddedTerminalTabModel.workingDirectoryURL(from: nil) == nil)
    }

    @Test("zsh terminal configuration installs cwd integration directory")
    func zshTerminalConfigurationInstallsCWDIntegrationDirectory() throws {
        let configuration = EmbeddedTerminalShellIntegration.configuration(
            forShell: "/bin/zsh",
            processEnvironment: [
                "HOME": "/Users/hunter",
                "USER": "hunter",
                "PATH": "/usr/bin:/bin"
            ]
        )
        let environment: [String: String] = Dictionary(uniqueKeysWithValues: configuration.environment.compactMap { item -> (String, String)? in
            let pair = item.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { return nil }
            return (pair[0], pair[1])
        })

        #expect(configuration.executable == "/bin/zsh")
        #expect(configuration.execName == "-zsh")
        #expect(environment["TERM"] == "xterm-256color")
        #expect(environment["ZDOTDIR"]?.hasSuffix("/DualFinder/ShellIntegration") == true)
    }

    @Test("terminal tab starts a PTY session")
    func terminalTabStartsPTYSession() async throws {
        let tab = EmbeddedTerminalTabModel(workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true))

        tab.startIfNeeded()
        #expect(tab.isRunning)

        tab.stop()
        try await Task.sleep(for: .milliseconds(100))
    }
}
