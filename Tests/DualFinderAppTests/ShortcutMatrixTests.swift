import AppKit
import Foundation
import Testing
@testable import DualFinderApp

@Suite("ShortcutMatrix")
struct ShortcutMatrixTests {
    @Test("stores resets and detects shortcut conflicts")
    func storesResetsAndDetectsConflicts() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let binding = AppShortcutBinding(key: "k", keyCode: nil, modifiers: [.command, .shift])

        AppShortcutMatrix.setBinding(binding, for: .newActiveTab, defaults: defaults)
        AppShortcutMatrix.setBinding(binding, for: .closeActiveTab, defaults: defaults)

        #expect(AppShortcutMatrix.binding(for: .newActiveTab, defaults: defaults) == binding)
        #expect(Set(AppShortcutMatrix.conflicts(defaults: defaults)[binding] ?? []) == [.newActiveTab, .closeActiveTab])

        AppShortcutMatrix.reset(defaults: defaults)

        #expect(AppShortcutMatrix.binding(for: .newActiveTab, defaults: defaults) == AppShortcutAction.newActiveTab.defaultBinding)
        #expect(AppShortcutMatrix.conflicts(defaults: defaults).isEmpty)
    }

    @Test("matches actions by key code before character fallback")
    func matchesActionsByKeyCodeBeforeCharacterFallback() throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        AppShortcutMatrix.setBinding(
            AppShortcutBinding(key: "right", keyCode: 124, modifiers: [.command, .control]),
            for: .copyLeftSelectionToRight,
            defaults: defaults
        )
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "",
            charactersIgnoringModifiers: "",
            isARepeat: false,
            keyCode: 124
        ))

        #expect(AppShortcutMatrix.action(matching: event, defaults: defaults) == .copyLeftSelectionToRight)
    }

    @Test("formats shortcut display text in modifier sort order")
    func formatsShortcutDisplayText() {
        let binding = AppShortcutBinding(key: "left", keyCode: 123, modifiers: [.shift, .command, .option])

        #expect(binding.displayText == "⌘⌥⇧←")
        #expect(AppShortcutBinding(key: "space", keyCode: 49, modifiers: [.control]).displayText == "⌃Space")
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "DualFinder.ShortcutMatrixTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
