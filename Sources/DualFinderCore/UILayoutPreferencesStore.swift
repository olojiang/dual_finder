import CoreGraphics
import Foundation

public enum FileListColumn: String, Codable, CaseIterable, Sendable {
    case type
    case encoding
    case size
    case modified
}

public enum FileListColumnBoundary: String, CaseIterable, Sendable {
    case afterName
    case afterType
    case afterEncoding
    case afterSize

    public var resizedColumn: FileListColumn {
        resizedColumn(showsEncoding: false)
    }

    public func resizedColumn(showsEncoding: Bool) -> FileListColumn {
        switch self {
        case .afterName:
            return .type
        case .afterType:
            return showsEncoding ? .encoding : .size
        case .afterEncoding:
            return .size
        case .afterSize:
            return .modified
        }
    }

    public func columnDelta(forDragDelta delta: Double) -> Double {
        -delta
    }
}

public struct FileListColumnWidths: Codable, Equatable, Sendable {
    public var type: Double
    public var encoding: Double
    public var size: Double
    public var modified: Double

    public init(type: Double, encoding: Double = Self.defaultEncodingWidth, size: Double, modified: Double) {
        self.type = type
        self.encoding = encoding
        self.size = size
        self.modified = modified
    }

    public static let defaultEncodingWidth: Double = 92
    public static let `default` = FileListColumnWidths(type: 112, encoding: defaultEncodingWidth, size: 86, modified: 126)

    public static let minimums = FileListColumnWidths(type: 64, encoding: 70, size: 56, modified: 88)
    public static let maximums = FileListColumnWidths(type: 280, encoding: 150, size: 160, modified: 240)

    private enum CodingKeys: String, CodingKey {
        case type
        case encoding
        case size
        case modified
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(Double.self, forKey: .type)
        encoding = try container.decodeIfPresent(Double.self, forKey: .encoding) ?? Self.defaultEncodingWidth
        size = try container.decode(Double.self, forKey: .size)
        modified = try container.decode(Double.self, forKey: .modified)
    }

    public func clamped() -> FileListColumnWidths {
        FileListColumnWidths(
            type: min(max(type, Self.minimums.type), Self.maximums.type),
            encoding: min(max(encoding, Self.minimums.encoding), Self.maximums.encoding),
            size: min(max(size, Self.minimums.size), Self.maximums.size),
            modified: min(max(modified, Self.minimums.modified), Self.maximums.modified)
        )
    }

    public func width(for column: FileListColumn) -> CGFloat {
        switch column {
        case .type: CGFloat(type)
        case .encoding: CGFloat(encoding)
        case .size: CGFloat(size)
        case .modified: CGFloat(modified)
        }
    }

    public mutating func adjust(_ column: FileListColumn, by delta: Double) {
        switch column {
        case .type: type += delta
        case .encoding: encoding += delta
        case .size: size += delta
        case .modified: modified += delta
        }
        self = clamped()
    }
}

public struct UILayoutPreferences: Codable, Equatable, Sendable {
    public var leftColumnWidths: FileListColumnWidths
    public var rightColumnWidths: FileListColumnWidths
    public var leftPaneFraction: Double
    public var isSidebarCollapsed: Bool
    public var isEncodingColumnVisible: Bool

    public init(
        leftColumnWidths: FileListColumnWidths = .default,
        rightColumnWidths: FileListColumnWidths = .default,
        leftPaneFraction: Double = 0.5,
        isSidebarCollapsed: Bool = false,
        isEncodingColumnVisible: Bool = false
    ) {
        self.leftColumnWidths = leftColumnWidths.clamped()
        self.rightColumnWidths = rightColumnWidths.clamped()
        self.leftPaneFraction = Self.clampedFraction(leftPaneFraction)
        self.isSidebarCollapsed = isSidebarCollapsed
        self.isEncodingColumnVisible = isEncodingColumnVisible
    }

    private enum CodingKeys: String, CodingKey {
        case leftColumnWidths
        case rightColumnWidths
        case columnWidths
        case leftPaneFraction
        case isSidebarCollapsed
        case isEncodingColumnVisible
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let leftColumnWidths = try container.decodeIfPresent(FileListColumnWidths.self, forKey: .leftColumnWidths),
           let rightColumnWidths = try container.decodeIfPresent(FileListColumnWidths.self, forKey: .rightColumnWidths) {
            self.leftColumnWidths = leftColumnWidths
            self.rightColumnWidths = rightColumnWidths
        } else if let shared = try container.decodeIfPresent(FileListColumnWidths.self, forKey: .columnWidths) {
            self.leftColumnWidths = shared
            self.rightColumnWidths = shared
        } else {
            self.leftColumnWidths = .default
            self.rightColumnWidths = .default
        }
        self.leftPaneFraction = try container.decodeIfPresent(Double.self, forKey: .leftPaneFraction)
            .map(Self.clampedFraction) ?? 0.5
        self.isSidebarCollapsed = try container.decodeIfPresent(Bool.self, forKey: .isSidebarCollapsed) ?? false
        self.isEncodingColumnVisible = try container.decodeIfPresent(Bool.self, forKey: .isEncodingColumnVisible) ?? false
        clamp()
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(leftColumnWidths, forKey: .leftColumnWidths)
        try container.encode(rightColumnWidths, forKey: .rightColumnWidths)
        try container.encode(leftPaneFraction, forKey: .leftPaneFraction)
        try container.encode(isSidebarCollapsed, forKey: .isSidebarCollapsed)
        try container.encode(isEncodingColumnVisible, forKey: .isEncodingColumnVisible)
    }

    public static let `default` = UILayoutPreferences()

    public static let sidebarCollapsedWidth: Double = 52
    public static let sidebarExpandedWidth: Double = 220
    public static let minimumLeftPaneFraction: Double = 0.2
    public static let maximumLeftPaneFraction: Double = 0.8

    public var sidebarWidth: Double {
        isSidebarCollapsed ? Self.sidebarCollapsedWidth : Self.sidebarExpandedWidth
    }

    public func columnWidths(for side: PaneSide) -> FileListColumnWidths {
        switch side {
        case .left: leftColumnWidths
        case .right: rightColumnWidths
        }
    }

    public mutating func setColumnWidths(_ widths: FileListColumnWidths, for side: PaneSide) {
        switch side {
        case .left: leftColumnWidths = widths.clamped()
        case .right: rightColumnWidths = widths.clamped()
        }
    }

    public mutating func clamp() {
        leftColumnWidths = leftColumnWidths.clamped()
        rightColumnWidths = rightColumnWidths.clamped()
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
