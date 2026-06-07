import Foundation

/// Modifier keys supported by the global show-window shortcut.
public enum ShowWindowHotkeyModifier: String, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case command
    case option
    case control
    case shift

    public var id: String { rawValue }

    public static func < (lhs: ShowWindowHotkeyModifier, rhs: ShowWindowHotkeyModifier) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }

    private var sortOrder: Int {
        switch self {
        case .control: 0
        case .option: 1
        case .shift: 2
        case .command: 3
        }
    }

    public var label: String {
        switch self {
        case .command: "⌘"
        case .option: "⌥"
        case .control: "⌃"
        case .shift: "⇧"
        }
    }
}

public struct ShowWindowHotkeyKeyChoice: Identifiable, Hashable, Sendable {
    public let id: String
    public let label: String
    public let keyCode: UInt16

    public init(id: String, label: String, keyCode: UInt16) {
        self.id = id
        self.label = label
        self.keyCode = keyCode
    }
}

public struct ShowWindowHotkeyBinding: Codable, Equatable, Hashable, Sendable {
    public var key: String
    public var keyCode: UInt16
    public var modifiers: Set<ShowWindowHotkeyModifier>

    public init(key: String, keyCode: UInt16, modifiers: Set<ShowWindowHotkeyModifier>) {
        self.key = key
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public static let `default` = ShowWindowHotkeyBinding(
        key: "d",
        keyCode: 2,
        modifiers: [.command, .control]
    )

    public var displayLabel: String {
        modifiers.sorted().map(\.label).joined() + key.uppercased()
    }

    public var usesCommand: Bool { modifiers.contains(.command) }
    public var usesShift: Bool { modifiers.contains(.shift) }
    public var usesOption: Bool { modifiers.contains(.option) }
    public var usesControl: Bool { modifiers.contains(.control) }

    public var isValid: Bool {
        guard Self.allowedKeys.contains(where: { $0.id == key && $0.keyCode == keyCode }) else {
            return false
        }
        return modifiers.contains(.command) || modifiers.contains(.control) || modifiers.contains(.option)
    }

    public static let allowedKeys: [ShowWindowHotkeyKeyChoice] = [
        ShowWindowHotkeyKeyChoice(id: "a", label: "A", keyCode: 0),
        ShowWindowHotkeyKeyChoice(id: "b", label: "B", keyCode: 11),
        ShowWindowHotkeyKeyChoice(id: "c", label: "C", keyCode: 8),
        ShowWindowHotkeyKeyChoice(id: "d", label: "D", keyCode: 2),
        ShowWindowHotkeyKeyChoice(id: "e", label: "E", keyCode: 14),
        ShowWindowHotkeyKeyChoice(id: "f", label: "F", keyCode: 3),
        ShowWindowHotkeyKeyChoice(id: "g", label: "G", keyCode: 5),
        ShowWindowHotkeyKeyChoice(id: "h", label: "H", keyCode: 4),
        ShowWindowHotkeyKeyChoice(id: "i", label: "I", keyCode: 34),
        ShowWindowHotkeyKeyChoice(id: "j", label: "J", keyCode: 38),
        ShowWindowHotkeyKeyChoice(id: "k", label: "K", keyCode: 40),
        ShowWindowHotkeyKeyChoice(id: "l", label: "L", keyCode: 37),
        ShowWindowHotkeyKeyChoice(id: "m", label: "M", keyCode: 46),
        ShowWindowHotkeyKeyChoice(id: "n", label: "N", keyCode: 45),
        ShowWindowHotkeyKeyChoice(id: "o", label: "O", keyCode: 31),
        ShowWindowHotkeyKeyChoice(id: "p", label: "P", keyCode: 35),
        ShowWindowHotkeyKeyChoice(id: "q", label: "Q", keyCode: 12),
        ShowWindowHotkeyKeyChoice(id: "r", label: "R", keyCode: 15),
        ShowWindowHotkeyKeyChoice(id: "s", label: "S", keyCode: 1),
        ShowWindowHotkeyKeyChoice(id: "t", label: "T", keyCode: 17),
        ShowWindowHotkeyKeyChoice(id: "u", label: "U", keyCode: 32),
        ShowWindowHotkeyKeyChoice(id: "v", label: "V", keyCode: 9),
        ShowWindowHotkeyKeyChoice(id: "w", label: "W", keyCode: 13),
        ShowWindowHotkeyKeyChoice(id: "x", label: "X", keyCode: 7),
        ShowWindowHotkeyKeyChoice(id: "y", label: "Y", keyCode: 16),
        ShowWindowHotkeyKeyChoice(id: "z", label: "Z", keyCode: 6),
        ShowWindowHotkeyKeyChoice(id: "0", label: "0", keyCode: 29),
        ShowWindowHotkeyKeyChoice(id: "1", label: "1", keyCode: 18),
        ShowWindowHotkeyKeyChoice(id: "2", label: "2", keyCode: 19),
        ShowWindowHotkeyKeyChoice(id: "3", label: "3", keyCode: 20),
        ShowWindowHotkeyKeyChoice(id: "4", label: "4", keyCode: 21),
        ShowWindowHotkeyKeyChoice(id: "5", label: "5", keyCode: 23),
        ShowWindowHotkeyKeyChoice(id: "6", label: "6", keyCode: 22),
        ShowWindowHotkeyKeyChoice(id: "7", label: "7", keyCode: 26),
        ShowWindowHotkeyKeyChoice(id: "8", label: "8", keyCode: 28),
        ShowWindowHotkeyKeyChoice(id: "9", label: "9", keyCode: 25)
    ]
}

public enum ShowWindowHotkeyStoreError: Error, Equatable, Sendable {
    case invalidBinding
}

public struct ShowWindowHotkeyStore {
    public static let didChangeNotification = Notification.Name("ShowWindowHotkeyStore.didChange")
    public static let distributedDidChangeNotification = Notification.Name("com.local.dualfinder.show-window-hotkey.did-change")

    private let configurationURL: URL
    private let fileManager: FileManager

    public init(configurationURL: URL = Self.defaultConfigurationURL, fileManager: FileManager = .default) {
        self.configurationURL = configurationURL
        self.fileManager = fileManager
    }

    public func binding() -> ShowWindowHotkeyBinding {
        guard let data = try? Data(contentsOf: configurationURL),
              let binding = try? JSONDecoder().decode(ShowWindowHotkeyBinding.self, from: data),
              binding.isValid
        else {
            return .default
        }
        return binding
    }

    public func setBinding(_ binding: ShowWindowHotkeyBinding) throws {
        guard binding.isValid else {
            throw ShowWindowHotkeyStoreError.invalidBinding
        }
        try fileManager.createDirectory(
            at: configurationURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(binding)
        try data.write(to: configurationURL, options: .atomic)
        postChangeNotifications()
    }

    public func reset() throws {
        if fileManager.fileExists(atPath: configurationURL.path) {
            try fileManager.removeItem(at: configurationURL)
        }
        postChangeNotifications()
    }

    private func postChangeNotifications() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
        DistributedNotificationCenter.default().postNotificationName(
            Self.distributedDidChangeNotification,
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    public static var defaultConfigurationURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("com.local.dualfinder", isDirectory: true)
            .appendingPathComponent("show-window-hotkey.json")
    }
}

/// Global shortcut to bring Dual Finder to the front (⌃⌘D).
public enum ShowWindowHotkeyDescriptor {
    public static let keyCharacter = ShowWindowHotkeyBinding.default.key
    public static let keyCode = ShowWindowHotkeyBinding.default.keyCode
    public static let usesCommand = ShowWindowHotkeyBinding.default.usesCommand
    public static let usesShift = ShowWindowHotkeyBinding.default.usesShift
    public static let usesOption = ShowWindowHotkeyBinding.default.usesOption
    public static let usesControl = ShowWindowHotkeyBinding.default.usesControl

    public static let displayLabel = ShowWindowHotkeyBinding.default.displayLabel
}
