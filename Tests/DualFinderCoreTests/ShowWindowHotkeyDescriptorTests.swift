import Foundation
import Testing
@testable import DualFinderCore

@Suite("ShowWindowHotkeyDescriptor")
struct ShowWindowHotkeyDescriptorTests {
    @Test("matches control command D")
    func keyBinding() {
        #expect(ShowWindowHotkeyDescriptor.keyCharacter == "d")
        #expect(ShowWindowHotkeyDescriptor.keyCode == 2)
        #expect(ShowWindowHotkeyDescriptor.usesCommand)
        #expect(!ShowWindowHotkeyDescriptor.usesShift)
        #expect(!ShowWindowHotkeyDescriptor.usesOption)
        #expect(ShowWindowHotkeyDescriptor.usesControl)
        #expect(ShowWindowHotkeyDescriptor.displayLabel == "⌃⌘D")
    }

    @Test("default binding is valid control command D")
    func defaultBinding() {
        let binding = ShowWindowHotkeyBinding.default

        #expect(binding.key == "d")
        #expect(binding.keyCode == 2)
        #expect(binding.modifiers == [.command, .control])
        #expect(binding.displayLabel == "⌃⌘D")
        #expect(binding.isValid)
    }

    @Test("store persists a custom binding")
    func storePersistsBinding() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let store = ShowWindowHotkeyStore(
            configurationURL: temporaryDirectory.url.appendingPathComponent("hotkey.json")
        )
        let binding = ShowWindowHotkeyBinding(
            key: "k",
            keyCode: 40,
            modifiers: [.command, .option]
        )

        try store.setBinding(binding)

        #expect(store.binding() == binding)
        #expect(store.binding().displayLabel == "⌥⌘K")
    }

    @Test("store rejects bindings without a global modifier")
    func storeRejectsInvalidBinding() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let store = ShowWindowHotkeyStore(
            configurationURL: temporaryDirectory.url.appendingPathComponent("hotkey.json")
        )
        let invalid = ShowWindowHotkeyBinding(key: "d", keyCode: 2, modifiers: [.shift])

        #expect(throws: ShowWindowHotkeyStoreError.invalidBinding) {
            try store.setBinding(invalid)
        }
        #expect(store.binding() == .default)
    }

    @Test("store rejects mismatched key codes")
    func storeRejectsMismatchedKeyCode() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let store = ShowWindowHotkeyStore(
            configurationURL: temporaryDirectory.url.appendingPathComponent("hotkey.json")
        )
        let invalid = ShowWindowHotkeyBinding(key: "d", keyCode: 40, modifiers: [.command])

        #expect(throws: ShowWindowHotkeyStoreError.invalidBinding) {
            try store.setBinding(invalid)
        }
        #expect(store.binding() == .default)
    }

    @Test("store falls back to default for unreadable binding data")
    func storeFallsBackForCorruptData() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let configurationURL = temporaryDirectory.url.appendingPathComponent("hotkey.json")
        try Data("not-json".utf8).write(to: configurationURL)
        let store = ShowWindowHotkeyStore(configurationURL: configurationURL)

        #expect(store.binding() == .default)
    }

    @Test("reset removes custom binding")
    func resetRemovesCustomBinding() throws {
        let temporaryDirectory = try TemporaryDirectory()
        let configurationURL = temporaryDirectory.url.appendingPathComponent("hotkey.json")
        let store = ShowWindowHotkeyStore(configurationURL: configurationURL)
        try store.setBinding(ShowWindowHotkeyBinding(key: "k", keyCode: 40, modifiers: [.command]))

        try store.reset()

        #expect(store.binding() == .default)
        #expect(!FileManager.default.fileExists(atPath: configurationURL.path))
    }
}
