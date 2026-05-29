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

    @Test("can select a child item while navigating")
    func selectsChildOnNavigation() {
        var pane = PaneState(side: .left, initialURL: URL(fileURLWithPath: "/Users/hunter/Documents"))
        let child = pane.selectedURL

        pane.navigateSelectedTab(to: URL(fileURLWithPath: "/Users/hunter"), selecting: child)

        #expect(pane.selectedURL == URL(fileURLWithPath: "/Users/hunter"))
        #expect(pane.selectedItemURLs == [child])
    }

    @Test("tracks back and forward directory history for selected tab")
    func tracksDirectoryHistory() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")
        let third = URL(fileURLWithPath: "/tmp/third")
        var pane = PaneState(side: .left, initialURL: first)

        pane.navigateSelectedTab(to: second)
        pane.navigateSelectedTab(to: third)

        #expect(pane.canNavigateSelectedTabBack)
        #expect(!pane.canNavigateSelectedTabForward)
        #expect(pane.navigateSelectedTabBack() == second)
        #expect(pane.selectedURL == second)
        #expect(pane.canNavigateSelectedTabForward)
        #expect(pane.navigateSelectedTabBack() == first)
        #expect(pane.selectedURL == first)
        #expect(!pane.canNavigateSelectedTabBack)

        #expect(pane.navigateSelectedTabForward() == second)
        #expect(pane.selectedURL == second)
        pane.navigateSelectedTab(to: third)
        #expect(!pane.canNavigateSelectedTabForward)
    }

    @Test("keeps directory history per tab")
    func keepsHistoryPerTab() {
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")
        let other = URL(fileURLWithPath: "/tmp/other")
        var pane = PaneState(side: .left, initialURL: first)

        let otherTabID = pane.addTab(url: other)
        pane.navigateSelectedTab(to: URL(fileURLWithPath: "/tmp/other/deeper"))
        pane.selectedTabID = pane.tabs[0].id
        pane.navigateSelectedTab(to: second)

        #expect(pane.navigateSelectedTabBack() == first)
        pane.selectedTabID = otherTabID
        #expect(pane.navigateSelectedTabBack() == other)
    }

    @Test("restores selected tab from saved tabs")
    func restoresSelectedTab() {
        let first = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/first"))
        let second = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/second"))

        let pane = PaneState(side: .right, tabs: [first, second], selectedTabID: second.id)

        #expect(pane.tabs == [first, second])
        #expect(pane.selectedTabID == second.id)
        #expect(pane.selectedURL == second.url)
        #expect(pane.selectedItemURLs.isEmpty)
    }

    @Test("falls back to first tab when restored selected tab is missing")
    func restoresMissingSelectedTabToFirstTab() {
        let first = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/first"))
        let pane = PaneState(side: .left, tabs: [first], selectedTabID: UUID())

        #expect(pane.selectedTabID == first.id)
        #expect(pane.selectedURL == first.url)
    }
}
