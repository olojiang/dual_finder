import Foundation

public enum MainWindowIdentity {
    public static let title = "Dual Finder 纪"
}

/// Snapshot of an AppKit window used for testable main-window selection.
public struct WindowSelectionSnapshot: Equatable, Sendable {
    public let windowNumber: Int
    public let title: String
    public let isMiniaturized: Bool
    public let isVisible: Bool
    public let canBecomeMain: Bool
    public let isSheet: Bool
    public let level: Int

    public init(
        windowNumber: Int,
        title: String,
        isMiniaturized: Bool,
        isVisible: Bool,
        canBecomeMain: Bool,
        isSheet: Bool,
        level: Int
    ) {
        self.windowNumber = windowNumber
        self.title = title
        self.isMiniaturized = isMiniaturized
        self.isVisible = isVisible
        self.canBecomeMain = canBecomeMain
        self.isSheet = isSheet
        self.level = level
    }

    public var isNormalLevel: Bool {
        level == 0
    }
}

public enum MainWindowSelector {
    /// Picks the primary content window, preferring the app title and miniaturized main windows.
    public static func select(
        from windows: [WindowSelectionSnapshot],
        preferredTitle: String = MainWindowIdentity.title
    ) -> WindowSelectionSnapshot? {
        let normal = windows.filter { !$0.isSheet && $0.isNormalLevel }
        guard !normal.isEmpty else { return nil }

        if let titled = normal.first(where: { $0.title == preferredTitle }) {
            return titled
        }

        if let miniaturized = normal.first(where: \.isMiniaturized) {
            return miniaturized
        }

        if let mainCapable = normal.first(where: \.canBecomeMain) {
            return mainCapable
        }

        return normal.first
    }
}
