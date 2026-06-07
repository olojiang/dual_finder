import Foundation
import Testing
@testable import DualFinderCore

@Suite("UILayoutPreferencesStore")
struct UILayoutPreferencesStoreTests {
    @Test("persists column widths, pane fraction, and sidebar collapse state")
    func persistsPreferences() {
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UILayoutPreferencesStore(defaults: defaults)
        let preferences = UILayoutPreferences(
            columnWidths: FileListColumnWidths(type: 140, size: 100, modified: 150),
            leftPaneFraction: 0.62,
            isSidebarCollapsed: true
        )

        store.save(preferences)
        let restored = store.load()

        #expect(restored.columnWidths == preferences.columnWidths)
        #expect(restored.leftPaneFraction == preferences.leftPaneFraction)
        #expect(restored.isSidebarCollapsed)
    }

    @Test("clamps invalid values on load and save")
    func clampsInvalidValues() {
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UILayoutPreferencesStore(defaults: defaults)
        let preferences = UILayoutPreferences(
            columnWidths: FileListColumnWidths(type: 20, size: 900, modified: 10),
            leftPaneFraction: 0.05,
            isSidebarCollapsed: false
        )

        store.save(preferences)
        let restored = store.load()

        #expect(restored.columnWidths == FileListColumnWidths(type: 64, size: 160, modified: 88))
        #expect(restored.leftPaneFraction == UILayoutPreferences.minimumLeftPaneFraction)
    }

    @Test("returns defaults when no saved preferences exist")
    func fallsBackToDefaults() {
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let restored = UILayoutPreferencesStore(defaults: defaults).load()

        #expect(restored == .default)
    }

    @Test("column width helper adjusts and clamps individual columns")
    func adjustsColumnWidths() {
        var widths = FileListColumnWidths.default
        widths.adjust(.type, by: 40)
        widths.adjust(.size, by: -20)

        #expect(widths.type == 152)
        #expect(widths.size == 66)
    }

    @Test("sidebar width reflects collapsed state")
    func sidebarWidth() {
        let expanded = UILayoutPreferences(isSidebarCollapsed: false)
        let collapsed = UILayoutPreferences(isSidebarCollapsed: true)

        #expect(expanded.sidebarWidth == UILayoutPreferences.sidebarExpandedWidth)
        #expect(collapsed.sidebarWidth == UILayoutPreferences.sidebarCollapsedWidth)
    }
}
