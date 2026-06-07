import Testing
@testable import DualFinderCore

@Suite("MainWindowSelector")
struct MainWindowSelectorTests {
    @Test("prefers titled main window")
    func prefersTitle() {
        let windows = [
            WindowSelectionSnapshot(
                windowNumber: 1,
                title: "Settings",
                isMiniaturized: false,
                isVisible: true,
                canBecomeMain: true,
                isSheet: false,
                level: 0
            ),
            WindowSelectionSnapshot(
                windowNumber: 2,
                title: MainWindowIdentity.title,
                isMiniaturized: true,
                isVisible: false,
                canBecomeMain: false,
                isSheet: false,
                level: 0
            )
        ]

        let selected = MainWindowSelector.select(from: windows)
        #expect(selected?.windowNumber == 2)
    }

    @Test("prefers miniaturized window when title is unknown")
    func prefersMiniaturized() {
        let windows = [
            WindowSelectionSnapshot(
                windowNumber: 10,
                title: "",
                isMiniaturized: false,
                isVisible: true,
                canBecomeMain: true,
                isSheet: false,
                level: 0
            ),
            WindowSelectionSnapshot(
                windowNumber: 11,
                title: "Other",
                isMiniaturized: true,
                isVisible: false,
                canBecomeMain: false,
                isSheet: false,
                level: 0
            )
        ]

        let selected = MainWindowSelector.select(from: windows)
        #expect(selected?.windowNumber == 11)
    }

    @Test("ignores sheets and non-normal levels")
    func ignoresSheets() {
        let windows = [
            WindowSelectionSnapshot(
                windowNumber: 1,
                title: "Sheet",
                isMiniaturized: false,
                isVisible: true,
                canBecomeMain: true,
                isSheet: true,
                level: 0
            ),
            WindowSelectionSnapshot(
                windowNumber: 2,
                title: "Floating",
                isMiniaturized: false,
                isVisible: true,
                canBecomeMain: true,
                isSheet: false,
                level: 3
            )
        ]

        #expect(MainWindowSelector.select(from: windows) == nil)
    }
}
