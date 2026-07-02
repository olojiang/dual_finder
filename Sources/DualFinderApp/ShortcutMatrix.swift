import AppKit
import Foundation
import SwiftUI

enum AppShortcutAction: String, CaseIterable, Identifiable {
    case newActiveTab
    case newRightTab
    case newFolder
    case goToFolder
    case fileSearch
    case flatView
    case folderBookmarks
    case batchRename
    case closeActiveTab
    case showShortcutHelp
    case focusLeftPane
    case focusRightPane
    case switchPane
    case selectTab1
    case selectTab2
    case selectTab3
    case selectTab4
    case selectTab5
    case selectTab6
    case selectTab7
    case selectTab8
    case selectTab9
    case navigateBack
    case navigateForward
    case copyLeftSelectionToRight
    case copyRightSelectionToLeft
    case moveLeftSelectionToRight
    case moveRightSelectionToLeft

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newActiveTab: "New Tab in Active Pane"
        case .newRightTab: "New Right Tab"
        case .newFolder: "New Folder"
        case .goToFolder: "Go to Folder"
        case .fileSearch: "Filter Current Folder"
        case .flatView: "Flat View"
        case .folderBookmarks: "Open Locations"
        case .batchRename: "Batch Rename"
        case .closeActiveTab: "Close Active Tab"
        case .showShortcutHelp: "Keyboard Shortcuts"
        case .focusLeftPane: "Focus Left Pane"
        case .focusRightPane: "Focus Right Pane"
        case .switchPane: "Switch Left/Right Pane"
        case .selectTab1: "Select Tab 1"
        case .selectTab2: "Select Tab 2"
        case .selectTab3: "Select Tab 3"
        case .selectTab4: "Select Tab 4"
        case .selectTab5: "Select Tab 5"
        case .selectTab6: "Select Tab 6"
        case .selectTab7: "Select Tab 7"
        case .selectTab8: "Select Tab 8"
        case .selectTab9: "Select Tab 9"
        case .navigateBack: "History Back"
        case .navigateForward: "History Forward"
        case .copyLeftSelectionToRight: "Copy Left Selection to Right"
        case .copyRightSelectionToLeft: "Copy Right Selection to Left"
        case .moveLeftSelectionToRight: "Move Left Selection to Right"
        case .moveRightSelectionToLeft: "Move Right Selection to Left"
        }
    }

    var group: String {
        switch self {
        case .goToFolder, .fileSearch, .flatView, .folderBookmarks, .batchRename, .showShortcutHelp:
            "Commands"
        case .newActiveTab, .newRightTab, .closeActiveTab:
            "Tabs"
        case .focusLeftPane, .focusRightPane, .switchPane, .navigateBack, .navigateForward:
            "Navigation"
        case .selectTab1, .selectTab2, .selectTab3, .selectTab4, .selectTab5, .selectTab6, .selectTab7, .selectTab8, .selectTab9:
            "Tabs"
        case .newFolder, .copyLeftSelectionToRight, .copyRightSelectionToLeft, .moveLeftSelectionToRight, .moveRightSelectionToLeft:
            "File Operations"
        }
    }

    var tabIndex: Int? {
        switch self {
        case .selectTab1: 0
        case .selectTab2: 1
        case .selectTab3: 2
        case .selectTab4: 3
        case .selectTab5: 4
        case .selectTab6: 5
        case .selectTab7: 6
        case .selectTab8: 7
        case .selectTab9: 8
        default: nil
        }
    }

    var defaultBinding: AppShortcutBinding {
        switch self {
        case .newActiveTab:
            AppShortcutBinding(key: "t", keyCode: nil, modifiers: [.command])
        case .newRightTab:
            AppShortcutBinding(key: "t", keyCode: nil, modifiers: [.command, .shift])
        case .newFolder:
            AppShortcutBinding(key: "n", keyCode: nil, modifiers: [.command, .shift])
        case .goToFolder:
            AppShortcutBinding(key: "g", keyCode: nil, modifiers: [.command, .shift])
        case .fileSearch:
            AppShortcutBinding(key: "s", keyCode: 1, modifiers: [.control])
        case .flatView:
            AppShortcutBinding(key: "b", keyCode: 11, modifiers: [.control])
        case .folderBookmarks:
            AppShortcutBinding(key: "d", keyCode: nil, modifiers: [.control])
        case .batchRename:
            AppShortcutBinding(key: "m", keyCode: nil, modifiers: [.control])
        case .closeActiveTab:
            AppShortcutBinding(key: "w", keyCode: nil, modifiers: [.command])
        case .showShortcutHelp:
            AppShortcutBinding(key: "/", keyCode: 44, modifiers: [.command, .shift])
        case .focusLeftPane:
            AppShortcutBinding(key: "left", keyCode: 123, modifiers: [.command])
        case .focusRightPane:
            AppShortcutBinding(key: "right", keyCode: 124, modifiers: [.command])
        case .switchPane:
            AppShortcutBinding(key: "tab", keyCode: 48, modifiers: [])
        case .selectTab1:
            AppShortcutBinding(key: "1", keyCode: nil, modifiers: [.command])
        case .selectTab2:
            AppShortcutBinding(key: "2", keyCode: nil, modifiers: [.command])
        case .selectTab3:
            AppShortcutBinding(key: "3", keyCode: nil, modifiers: [.command])
        case .selectTab4:
            AppShortcutBinding(key: "4", keyCode: nil, modifiers: [.command])
        case .selectTab5:
            AppShortcutBinding(key: "5", keyCode: nil, modifiers: [.command])
        case .selectTab6:
            AppShortcutBinding(key: "6", keyCode: nil, modifiers: [.command])
        case .selectTab7:
            AppShortcutBinding(key: "7", keyCode: nil, modifiers: [.command])
        case .selectTab8:
            AppShortcutBinding(key: "8", keyCode: nil, modifiers: [.command])
        case .selectTab9:
            AppShortcutBinding(key: "9", keyCode: nil, modifiers: [.command])
        case .navigateBack:
            AppShortcutBinding(key: "[", keyCode: 33, modifiers: [.control])
        case .navigateForward:
            AppShortcutBinding(key: "]", keyCode: 30, modifiers: [.control])
        case .copyLeftSelectionToRight:
            AppShortcutBinding(key: "right", keyCode: 124, modifiers: [.command, .control])
        case .copyRightSelectionToLeft:
            AppShortcutBinding(key: "left", keyCode: 123, modifiers: [.command, .control])
        case .moveLeftSelectionToRight:
            AppShortcutBinding(key: "right", keyCode: 124, modifiers: [.command, .option])
        case .moveRightSelectionToLeft:
            AppShortcutBinding(key: "left", keyCode: 123, modifiers: [.command, .option])
        }
    }
}

enum AppShortcutModifier: String, Codable, CaseIterable, Comparable, Identifiable {
    case command
    case option
    case control
    case shift

    var id: String { rawValue }

    static func < (lhs: AppShortcutModifier, rhs: AppShortcutModifier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    var sortOrder: Int {
        switch self {
        case .command: 0
        case .option: 1
        case .control: 2
        case .shift: 3
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .command: .command
        case .option: .option
        case .control: .control
        case .shift: .shift
        }
    }

    var label: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
}

struct AppShortcutBinding: Codable, Equatable, Hashable {
    var key: String
    var keyCode: UInt16?
    var modifiers: Set<AppShortcutModifier>

    init(key: String, keyCode: UInt16?, modifiers: Set<AppShortcutModifier>) {
        self.key = key
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    var displayText: String {
        let modifierText = modifiers.sorted().map(\.label).joined()
        return modifierText + displayKey
    }

    private var displayKey: String {
        switch key {
        case "left": "←"
        case "right": "→"
        case "up": "↑"
        case "down": "↓"
        case "space": "Space"
        case "delete": "Delete"
        default: key.uppercased()
        }
    }
}

struct ShortcutKeyChoice: Identifiable, Hashable {
    let id: String
    let label: String
    let keyCode: UInt16?
}

enum AppShortcutMatrix {
    static let didChangeNotification = Notification.Name("AppShortcutMatrix.didChange")
    static let allowedKeys: [ShortcutKeyChoice] = {
        let letters = (UnicodeScalar("a").value...UnicodeScalar("z").value).compactMap { value -> ShortcutKeyChoice? in
            guard let scalar = UnicodeScalar(value) else { return nil }
            let key = String(Character(scalar))
            return ShortcutKeyChoice(id: key, label: key.uppercased(), keyCode: nil)
        }
        let digits = (1...9).map { ShortcutKeyChoice(id: "\($0)", label: "\($0)", keyCode: nil) }
        return letters + digits + [
            ShortcutKeyChoice(id: "[", label: "[", keyCode: 33),
            ShortcutKeyChoice(id: "]", label: "]", keyCode: 30),
            ShortcutKeyChoice(id: "left", label: "←", keyCode: 123),
            ShortcutKeyChoice(id: "right", label: "→", keyCode: 124),
            ShortcutKeyChoice(id: "up", label: "↑", keyCode: 126),
            ShortcutKeyChoice(id: "down", label: "↓", keyCode: 125),
            ShortcutKeyChoice(id: "space", label: "Space", keyCode: 49),
            ShortcutKeyChoice(id: "delete", label: "Delete", keyCode: 51),
            ShortcutKeyChoice(id: "tab", label: "Tab", keyCode: 48),
            ShortcutKeyChoice(id: "/", label: "/", keyCode: 44)
        ]
    }()

    static func binding(for action: AppShortcutAction, defaults: UserDefaults = .standard) -> AppShortcutBinding {
        guard let data = defaults.data(forKey: storageKey(for: action)),
              let binding = try? JSONDecoder().decode(AppShortcutBinding.self, from: data)
        else {
            return action.defaultBinding
        }
        return binding
    }

    static func setBinding(_ binding: AppShortcutBinding, for action: AppShortcutAction, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(binding) {
            defaults.set(data, forKey: storageKey(for: action))
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static func reset(defaults: UserDefaults = .standard) {
        for action in AppShortcutAction.allCases {
            defaults.removeObject(forKey: storageKey(for: action))
        }
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }

    static func action(matching event: NSEvent, defaults: UserDefaults = .standard) -> AppShortcutAction? {
        AppShortcutAction.allCases.first { action in
            binding(for: action, defaults: defaults).matches(event)
        }
    }

    static func conflicts(defaults: UserDefaults = .standard) -> [AppShortcutBinding: [AppShortcutAction]] {
        Dictionary(grouping: AppShortcutAction.allCases) { action in
            binding(for: action, defaults: defaults)
        }
        .filter { _, actions in actions.count > 1 }
    }

    private static func storageKey(for action: AppShortcutAction) -> String {
        "shortcutMatrix.v1.\(action.rawValue)"
    }
}

private extension AppShortcutBinding {
    func matches(_ event: NSEvent) -> Bool {
        let eventFlags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let expectedFlags = modifiers.reduce(NSEvent.ModifierFlags()) { result, modifier in
            result.union(modifier.flag)
        }
        guard eventFlags == expectedFlags else { return false }

        if let keyCode, event.keyCode == keyCode {
            return true
        }

        return event.charactersIgnoringModifiers?.lowercased() == key.lowercased()
    }
}
