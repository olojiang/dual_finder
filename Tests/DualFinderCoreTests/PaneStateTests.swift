import Foundation
import Testing
@testable import DualFinderCore

@Suite("PaneState")
struct PaneStateTests {
    @Test("adds and closes tabs while keeping at least one tab")
    func managesTabs() {
        let first = URL(fileURLWithPath: "/tmp")
        var pane = PaneState(side: .left, initialURL: first)

        let second = pane.addTab(url: URL(fileURLWithPath: "/Users"))
        #expect(pane.tabs.count == 2)
        #expect(pane.selectedTabID == second)

        let didCloseSecond = pane.closeTab(id: second)
        #expect(didCloseSecond)
        #expect(pane.tabs.count == 1)
        #expect(pane.selectedTab?.url == first)

        let didCloseLastTab = pane.closeTab(id: pane.tabs[0].id)
        #expect(!didCloseLastTab)
        #expect(pane.tabs.count == 1)
    }

    @Test("clears selection on navigation")
    func managesSelection() {
        var pane = PaneState(side: .left, initialURL: URL(fileURLWithPath: "/tmp"))
        let selected = URL(fileURLWithPath: "/tmp/selected.txt")

        pane.selectedItemURLs = [selected]
        #expect(pane.selectedItemURLs == [selected])

        pane.navigateSelectedTab(to: URL(fileURLWithPath: "/Users"))
        #expect(pane.selectedItemURLs.isEmpty)
    }
}
