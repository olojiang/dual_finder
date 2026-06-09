import Foundation
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

    @Test("terminal tab starts a PTY session")
    func terminalTabStartsPTYSession() async throws {
        let tab = EmbeddedTerminalTabModel(workingDirectory: URL(fileURLWithPath: "/tmp", isDirectory: true))

        tab.startIfNeeded()
        #expect(tab.isRunning)

        tab.stop()
        try await Task.sleep(for: .milliseconds(100))
    }
}
