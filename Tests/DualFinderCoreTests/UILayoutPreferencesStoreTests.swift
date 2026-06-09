import Foundation
import Testing
@testable import DualFinderCore

@Suite("UILayoutPreferencesStore")
struct UILayoutPreferencesStoreTests {
    @Test("persists per-pane column widths, pane fraction, and sidebar collapse state")
    func persistsPreferences() {
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UILayoutPreferencesStore(defaults: defaults)
        let preferences = UILayoutPreferences(
            leftColumnWidths: FileListColumnWidths(type: 140, size: 100, modified: 150),
            rightColumnWidths: FileListColumnWidths(type: 120, size: 90, modified: 130),
            leftPaneFraction: 0.62,
            isSidebarCollapsed: true
        )

        store.save(preferences)
        let restored = store.load()

        #expect(restored.leftColumnWidths == preferences.leftColumnWidths)
        #expect(restored.rightColumnWidths == preferences.rightColumnWidths)
        #expect(restored.leftPaneFraction == preferences.leftPaneFraction)
        #expect(restored.isSidebarCollapsed)
    }

    @Test("migrates legacy shared columnWidths to both panes")
    func migratesLegacySharedColumnWidths() {
        let legacyJSON = """
        {
          "columnWidths": { "type": 130, "size": 95, "modified": 140 },
          "leftPaneFraction": 0.55,
          "isSidebarCollapsed": false
        }
        """
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(legacyJSON.utf8), forKey: "uiLayoutPreferences")

        let restored = UILayoutPreferencesStore(defaults: defaults).load()
        let expected = FileListColumnWidths(type: 130, size: 95, modified: 140)

        #expect(restored.leftColumnWidths == expected)
        #expect(restored.rightColumnWidths == expected)
        #expect(restored.leftPaneFraction == 0.55)
    }

    @Test("clamps invalid values on load and save")
    func clampsInvalidValues() {
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UILayoutPreferencesStore(defaults: defaults)
        let preferences = UILayoutPreferences(
            leftColumnWidths: FileListColumnWidths(type: 20, size: 900, modified: 10),
            rightColumnWidths: FileListColumnWidths(type: 300, size: 10, modified: 10),
            leftPaneFraction: 0.05,
            isSidebarCollapsed: false
        )

        store.save(preferences)
        let restored = store.load()

        #expect(restored.leftColumnWidths == FileListColumnWidths(type: 64, size: 160, modified: 88))
        #expect(restored.rightColumnWidths == FileListColumnWidths(type: 280, size: 56, modified: 88))
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

    @Test("columnWidths(for:) returns pane-specific widths")
    func columnWidthsForPane() {
        let preferences = UILayoutPreferences(
            leftColumnWidths: FileListColumnWidths(type: 100, size: 80, modified: 120),
            rightColumnWidths: FileListColumnWidths(type: 110, size: 85, modified: 125)
        )

        #expect(preferences.columnWidths(for: .left).type == 100)
        #expect(preferences.columnWidths(for: .right).type == 110)
    }

    @Test("sidebar width reflects collapsed state")
    func sidebarWidth() {
        let expanded = UILayoutPreferences(isSidebarCollapsed: false)
        let collapsed = UILayoutPreferences(isSidebarCollapsed: true)

        #expect(expanded.sidebarWidth == UILayoutPreferences.sidebarExpandedWidth)
        #expect(collapsed.sidebarWidth == UILayoutPreferences.sidebarCollapsedWidth)
    }
}

@Suite("FileListColumnBoundary")
struct FileListColumnBoundaryTests {
    @Test("resizes the fixed column to the right of each boundary")
    func resizedColumnMapping() {
        #expect(FileListColumnBoundary.afterName.resizedColumn == .type)
        #expect(FileListColumnBoundary.afterType.resizedColumn == .size)
        #expect(FileListColumnBoundary.afterSize.resizedColumn == .modified)
    }

    @Test("inverts drag delta so right-anchored boundaries follow the cursor")
    func columnDeltaInvertsDragDelta() {
        #expect(FileListColumnBoundary.afterName.columnDelta(forDragDelta: 24) == -24)
        #expect(FileListColumnBoundary.afterType.columnDelta(forDragDelta: -18) == 18)
        #expect(FileListColumnBoundary.afterSize.columnDelta(forDragDelta: 12) == -12)
    }
}
