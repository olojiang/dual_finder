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
        #expect(!restored.isEncodingColumnVisible)
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
        #expect(!restored.isEncodingColumnVisible)
    }

    @Test("persists encoding column visibility and migrates missing encoding widths")
    func persistsEncodingColumnPreferences() {
        let legacyJSON = """
        {
          "leftColumnWidths": { "type": 130, "size": 95, "modified": 140 },
          "rightColumnWidths": { "type": 120, "size": 85, "modified": 130 },
          "leftPaneFraction": 0.55,
          "isSidebarCollapsed": false,
          "isEncodingColumnVisible": true
        }
        """
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data(legacyJSON.utf8), forKey: "uiLayoutPreferences")

        let restored = UILayoutPreferencesStore(defaults: defaults).load()

        #expect(restored.isEncodingColumnVisible)
        #expect(restored.leftColumnWidths.encoding == FileListColumnWidths.defaultEncodingWidth)
        #expect(restored.rightColumnWidths.encoding == FileListColumnWidths.defaultEncodingWidth)
    }

    @Test("round-trip preserves custom encoding column widths")
    func roundTripsEncodingWidths() {
        let suiteName = "UILayoutPreferencesStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UILayoutPreferencesStore(defaults: defaults)
        let preferences = UILayoutPreferences(
            leftColumnWidths: FileListColumnWidths(type: 100, encoding: 110, size: 80, modified: 120),
            rightColumnWidths: FileListColumnWidths(type: 90, encoding: 100, size: 70, modified: 110),
            leftPaneFraction: 0.45,
            isSidebarCollapsed: false,
            isEncodingColumnVisible: true
        )

        store.save(preferences)
        let restored = store.load()

        #expect(restored.leftColumnWidths.encoding == 110)
        #expect(restored.rightColumnWidths.encoding == 100)
        #expect(restored.isEncodingColumnVisible)
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

    @Test("sidebar width reflects collapsed state")
    func sidebarWidth() {
        let expanded = UILayoutPreferences(isSidebarCollapsed: false)
        let collapsed = UILayoutPreferences(isSidebarCollapsed: true)

        #expect(expanded.sidebarWidth == UILayoutPreferences.sidebarExpandedWidth)
        #expect(collapsed.sidebarWidth == UILayoutPreferences.sidebarCollapsedWidth)
    }
}

@Suite("FileListColumnWidths")
struct FileListColumnWidthsTests {
    @Test("adjust clamps each column within bounds")
    func adjustClampsEachColumn() {
        var widths = FileListColumnWidths.default
        widths.adjust(.type, by: 40)
        widths.adjust(.encoding, by: 20)
        widths.adjust(.size, by: -20)

        #expect(widths.type == 152)
        #expect(widths.encoding == 112)
        #expect(widths.size == 66)
    }

    @Test("adjust(.modified) works correctly")
    func adjustModified() {
        var widths = FileListColumnWidths.default // modified = 126
        widths.adjust(.modified, by: 50)
        #expect(widths.modified == 176)

        widths.adjust(.modified, by: -100)
        #expect(widths.modified == 88) // clamped to minimum
    }

    @Test("adjust to exactly minimum and maximum boundaries")
    func adjustToBoundaries() {
        var widths = FileListColumnWidths(type: 100, size: 100, modified: 100)

        widths.adjust(.type, by: -36)
        #expect(widths.type == 64) // minimum

        widths.adjust(.type, by: -1)
        #expect(widths.type == 64) // stays at minimum

        widths = FileListColumnWidths(type: 250, size: 100, modified: 100)
        widths.adjust(.type, by: 30)
        #expect(widths.type == 280) // maximum

        widths.adjust(.type, by: 1)
        #expect(widths.type == 280) // stays at maximum
    }

    @Test("adjust encoding column respects bounds")
    func adjustEncodingBounds() {
        var widths = FileListColumnWidths.default // encoding = 92

        widths.adjust(.encoding, by: 100)
        #expect(widths.encoding == 150) // clamped to max

        widths.adjust(.encoding, by: -200)
        #expect(widths.encoding == 70) // clamped to min
    }

    @Test("width(for:) returns correct CGFloat values for all columns")
    func widthForColumn() {
        let widths = FileListColumnWidths(type: 130, encoding: 95, size: 80, modified: 140)

        #expect(widths.width(for: .type) == 130)
        #expect(widths.width(for: .encoding) == 95)
        #expect(widths.width(for: .size) == 80)
        #expect(widths.width(for: .modified) == 140)
    }

    @Test("clamped fixes all out-of-bounds values including encoding")
    func clampedFixesAllValues() {
        let widths = FileListColumnWidths(type: 10, encoding: 10, size: 200, modified: 300)
        let clamped = widths.clamped()

        #expect(clamped.type == FileListColumnWidths.minimums.type)
        #expect(clamped.encoding == FileListColumnWidths.minimums.encoding)
        #expect(clamped.size == FileListColumnWidths.maximums.size)
        #expect(clamped.modified == FileListColumnWidths.maximums.modified)
    }

    @Test("default encoding width is part of default widths")
    func defaultEncodingWidth() {
        #expect(FileListColumnWidths.default.encoding == FileListColumnWidths.defaultEncodingWidth)
    }
}

@Suite("UILayoutPreferences")
struct UILayoutPreferencesTests {
    @Test("columnWidths(for:) returns pane-specific widths")
    func columnWidthsForPane() {
        let preferences = UILayoutPreferences(
            leftColumnWidths: FileListColumnWidths(type: 100, size: 80, modified: 120),
            rightColumnWidths: FileListColumnWidths(type: 110, size: 85, modified: 125)
        )

        #expect(preferences.columnWidths(for: .left).type == 100)
        #expect(preferences.columnWidths(for: .right).type == 110)
    }

    @Test("setColumnWidths mutates the correct pane independently")
    func setColumnWidthsMutatesCorrectPane() {
        var preferences = UILayoutPreferences()
        let newLeft = FileListColumnWidths(type: 200, size: 120, modified: 180)
        let originalRight = preferences.rightColumnWidths

        preferences.setColumnWidths(newLeft, for: .left)

        #expect(preferences.leftColumnWidths == newLeft)
        #expect(preferences.rightColumnWidths == originalRight)

        let newRight = FileListColumnWidths(type: 150, size: 100, modified: 160)
        preferences.setColumnWidths(newRight, for: .right)

        #expect(preferences.rightColumnWidths == newRight)
        #expect(preferences.leftColumnWidths == newLeft)
    }

    @Test("setColumnWidths clamps out-of-bounds widths")
    func setColumnWidthsClamps() {
        var preferences = UILayoutPreferences()
        let oversized = FileListColumnWidths(type: 500, size: 500, modified: 500)

        preferences.setColumnWidths(oversized, for: .left)

        #expect(preferences.leftColumnWidths.type == FileListColumnWidths.maximums.type)
        #expect(preferences.leftColumnWidths.size == FileListColumnWidths.maximums.size)
        #expect(preferences.leftColumnWidths.modified == FileListColumnWidths.maximums.modified)
    }

    @Test("clampedFraction returns boundaries correctly")
    func clampedFractionBoundaries() {
        #expect(UILayoutPreferences.clampedFraction(0.0) == UILayoutPreferences.minimumLeftPaneFraction)
        #expect(UILayoutPreferences.clampedFraction(0.2) == 0.2)
        #expect(UILayoutPreferences.clampedFraction(0.5) == 0.5)
        #expect(UILayoutPreferences.clampedFraction(0.8) == 0.8)
        #expect(UILayoutPreferences.clampedFraction(0.9) == UILayoutPreferences.maximumLeftPaneFraction)
        #expect(UILayoutPreferences.clampedFraction(1.0) == UILayoutPreferences.maximumLeftPaneFraction)
        #expect(UILayoutPreferences.clampedFraction(-1.0) == UILayoutPreferences.minimumLeftPaneFraction)
    }

    @Test("default preferences match expected values")
    func defaultValues() {
        let d = UILayoutPreferences.default

        #expect(d.leftColumnWidths == .default)
        #expect(d.rightColumnWidths == .default)
        #expect(d.leftPaneFraction == 0.5)
        #expect(!d.isSidebarCollapsed)
        #expect(!d.isEncodingColumnVisible)
        #expect(d.sidebarWidth == UILayoutPreferences.sidebarExpandedWidth)
    }

    @Test("clamp fixes all fields")
    func clampFixesAll() {
        var prefs = UILayoutPreferences()
        prefs.leftColumnWidths = FileListColumnWidths(type: 10, encoding: 10, size: 10, modified: 10)
        prefs.rightColumnWidths = FileListColumnWidths(type: 999, encoding: 999, size: 999, modified: 999)
        prefs.leftPaneFraction = 0.01

        prefs.clamp()

        #expect(prefs.leftColumnWidths == FileListColumnWidths(type: 64, encoding: 70, size: 56, modified: 88))
        #expect(prefs.rightColumnWidths == FileListColumnWidths(type: 280, encoding: 150, size: 160, modified: 240))
        #expect(prefs.leftPaneFraction == UILayoutPreferences.minimumLeftPaneFraction)
    }
}

@Suite("FileListColumnBoundary")
struct FileListColumnBoundaryTests {
    @Test("resizedColumn without encoding returns correct mapping")
    func resizedColumnNoEncoding() {
        #expect(FileListColumnBoundary.afterName.resizedColumn == .type)
        #expect(FileListColumnBoundary.afterType.resizedColumn == .size)
        #expect(FileListColumnBoundary.afterEncoding.resizedColumn == .size)
        #expect(FileListColumnBoundary.afterSize.resizedColumn == .modified)
    }

    @Test("resizedColumn with encoding enabled returns correct mapping")
    func resizedColumnWithEncoding() {
        #expect(FileListColumnBoundary.afterName.resizedColumn(showsEncoding: true) == .type)
        #expect(FileListColumnBoundary.afterType.resizedColumn(showsEncoding: true) == .encoding)
        #expect(FileListColumnBoundary.afterEncoding.resizedColumn(showsEncoding: true) == .size)
        #expect(FileListColumnBoundary.afterSize.resizedColumn(showsEncoding: true) == .modified)
    }

    @Test("resizedColumn(showsEncoding: false) for afterEncoding falls back to size")
    func afterEncodingFallsBackToSize() {
        #expect(FileListColumnBoundary.afterEncoding.resizedColumn(showsEncoding: false) == .size)
    }

    @Test("columnDelta inverts drag delta for all boundaries")
    func columnDeltaInvertsDragDelta() {
        for boundary in FileListColumnBoundary.allCases {
            #expect(boundary.columnDelta(forDragDelta: 24) == -24)
            #expect(boundary.columnDelta(forDragDelta: -18) == 18)
            #expect(boundary.columnDelta(forDragDelta: 0) == 0)
        }
    }

    @Test("all boundaries are covered by allCases")
    func allCasesCoverage() {
        #expect(FileListColumnBoundary.allCases.count == 4)
        #expect(FileListColumnBoundary.allCases.contains(.afterName))
        #expect(FileListColumnBoundary.allCases.contains(.afterType))
        #expect(FileListColumnBoundary.allCases.contains(.afterEncoding))
        #expect(FileListColumnBoundary.allCases.contains(.afterSize))
    }
}
