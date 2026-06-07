import CoreGraphics
import Foundation

public enum FileListColumn: String, Codable, CaseIterable, Sendable {
    case type
    case size
    case modified
}

public struct FileListColumnWidths: Codable, Equatable, Sendable {
    public var type: Double
    public var size: Double
    public var modified: Double

    public init(type: Double, size: Double, modified: Double) {
        self.type = type
        self.size = size
        self.modified = modified
    }

    public static let `default` = FileListColumnWidths(type: 112, size: 86, modified: 126)

    public static let minimums = FileListColumnWidths(type: 64, size: 56, modified: 88)
    public static let maximums = FileListColumnWidths(type: 280, size: 160, modified: 240)

    public func clamped() -> FileListColumnWidths {
        FileListColumnWidths(
            type: min(max(type, Self.minimums.type), Self.maximums.type),
            size: min(max(size, Self.minimums.size), Self.maximums.size),
            modified: min(max(modified, Self.minimums.modified), Self.maximums.modified)
        )
    }

    public func width(for column: FileListColumn) -> CGFloat {
        switch column {
        case .type: CGFloat(type)
        case .size: CGFloat(size)
        case .modified: CGFloat(modified)
        }
    }

    public mutating func adjust(_ column: FileListColumn, by delta: Double) {
        switch column {
        case .type: type += delta
        case .size: size += delta
        case .modified: modified += delta
        }
        self = clamped()
    }
}

public struct UILayoutPreferences: Codable, Equatable, Sendable {
    public var columnWidths: FileListColumnWidths
    public var leftPaneFraction: Double
    public var isSidebarCollapsed: Bool

    public init(
        columnWidths: FileListColumnWidths = .default,
        leftPaneFraction: Double = 0.5,
        isSidebarCollapsed: Bool = false
    ) {
        self.columnWidths = columnWidths.clamped()
        self.leftPaneFraction = Self.clampedFraction(leftPaneFraction)
        self.isSidebarCollapsed = isSidebarCollapsed
    }

    public static let `default` = UILayoutPreferences()

    public static let sidebarCollapsedWidth: Double = 52
    public static let sidebarExpandedWidth: Double = 220
    public static let minimumLeftPaneFraction: Double = 0.2
    public static let maximumLeftPaneFraction: Double = 0.8

    public var sidebarWidth: Double {
        isSidebarCollapsed ? Self.sidebarCollapsedWidth : Self.sidebarExpandedWidth
    }

    public mutating func clamp() {
        columnWidths = columnWidths.clamped()
        leftPaneFraction = Self.clampedFraction(leftPaneFraction)
    }

    public static func clampedFraction(_ value: Double) -> Double {
        min(max(value, minimumLeftPaneFraction), maximumLeftPaneFraction)
    }
}

public final class UILayoutPreferencesStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "uiLayoutPreferences") {
        self.defaults = defaults
        self.key = key
    }

    public func load() -> UILayoutPreferences {
        guard let data = defaults.data(forKey: key),
              var preferences = try? JSONDecoder().decode(UILayoutPreferences.self, from: data)
        else {
            return .default
        }
        preferences.clamp()
        return preferences
    }

    public func save(_ preferences: UILayoutPreferences) {
        var clamped = preferences
        clamped.clamp()
        if let data = try? JSONEncoder().encode(clamped) {
            defaults.set(data, forKey: key)
        }
    }
}
