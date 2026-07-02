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

    @Test("resolves tabs by display order")
    func resolvesTabIDByDisplayOrder() {
        let first = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/first"))
        let second = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/second"))
        let pane = PaneState(side: .left, tabs: [first, second], selectedTabID: first.id)

        #expect(pane.tabID(atZeroBasedIndex: 0) == first.id)
        #expect(pane.tabID(atZeroBasedIndex: 1) == second.id)
        #expect(pane.tabID(atZeroBasedIndex: 2) == nil)
        #expect(pane.tabID(atZeroBasedIndex: -1) == nil)
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

    @Test("reorders tabs within the same pane")
    func reordersTabsWithinSamePane() {
        let first = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/first"))
        let second = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/second"))
        let third = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/third"))
        var pane = PaneState(side: .left, tabs: [first, second, third], selectedTabID: first.id)

        let moved = pane.moveTab(id: third.id, beforeTabID: first.id)
        #expect(moved)
        #expect(pane.tabs.map(\.id) == [third.id, first.id, second.id])
    }

    @Test("moves tabs between panes while keeping at least one tab")
    func movesTabsBetweenPanesWhileKeepingAtLeastOneTab() {
        let leftFirst = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/left-first"))
        let leftSecond = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/left-second"))
        let rightFirst = FileTab(id: UUID(), url: URL(fileURLWithPath: "/tmp/right-first"))
        var leftPane = PaneState(side: .left, tabs: [leftFirst, leftSecond], selectedTabID: leftFirst.id)
        var rightPane = PaneState(side: .right, tabs: [rightFirst], selectedTabID: rightFirst.id)
        let replacement = URL(fileURLWithPath: "/tmp/replacement")

        let detached = leftPane.detachTab(id: leftSecond.id, replacementURLIfEmpty: replacement)
        let inserted = rightPane.insertTab(leftSecond, beforeTabID: nil)
        #expect(detached?.id == leftSecond.id)
        #expect(leftPane.tabs.map(\.id) == [leftFirst.id])
        #expect(inserted)
        #expect(rightPane.tabs.map(\.id) == [rightFirst.id, leftSecond.id])
        #expect(rightPane.selectedTabID == leftSecond.id)

        let onlyTab = leftPane.detachTab(id: leftFirst.id, replacementURLIfEmpty: replacement)
        #expect(onlyTab?.id == leftFirst.id)
        #expect(leftPane.tabs.count == 1)
        #expect(leftPane.selectedURL == replacement)
    }
}
