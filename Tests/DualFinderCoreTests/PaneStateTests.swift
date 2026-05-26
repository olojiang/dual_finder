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

        pane.closeTab(id: second)
        #expect(pane.tabs.count == 1)
        #expect(pane.selectedTab?.url == first)

        pane.closeTab(id: pane.tabs[0].id)
        #expect(pane.tabs.count == 1)
    }
}
