import Foundation
import Testing
@testable import DualFinderCore

@Suite("PaneSessionStore")
struct PaneSessionStoreTests {
    @Test("persists tabs and selected tab for both panes")
    func persistsSession() {
        let suiteName = "PaneSessionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PaneSessionStore(defaults: defaults)
        var left = PaneState(side: .left, initialURL: URL(fileURLWithPath: "/tmp/left"))
        let selectedLeft = left.addTab(url: URL(fileURLWithPath: "/tmp/left/second"))
        var right = PaneState(side: .right, initialURL: URL(fileURLWithPath: "/tmp/right"))
        _ = right.addTab(url: URL(fileURLWithPath: "/tmp/right/second"))
        right.selectedTabID = right.tabs[0].id

        store.save(left: left, right: right)
        let restored = store.load(fallbackURL: URL(fileURLWithPath: "/tmp/fallback"))

        #expect(restored.left.tabs == left.tabs)
        #expect(restored.left.selectedTabID == selectedLeft)
        #expect(restored.left.selectedURL == URL(fileURLWithPath: "/tmp/left/second"))
        #expect(restored.right.tabs == right.tabs)
        #expect(restored.right.selectedTabID == right.tabs[0].id)
        #expect(restored.right.selectedURL == URL(fileURLWithPath: "/tmp/right"))
    }

    @Test("falls back to one tab per pane when no session exists")
    func fallsBackWithoutSession() {
        let suiteName = "PaneSessionStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let fallback = URL(fileURLWithPath: "/tmp/fallback")
        let restored = PaneSessionStore(defaults: defaults).load(fallbackURL: fallback)

        #expect(restored.left.tabs.count == 1)
        #expect(restored.left.selectedURL == fallback)
        #expect(restored.right.tabs.count == 1)
        #expect(restored.right.selectedURL == fallback)
    }
}
