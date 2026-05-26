import Foundation

public struct PaneSessionSnapshot: Codable, Equatable, Sendable {
    public let tabs: [FileTab]
    public let selectedTabID: UUID

    public init(pane: PaneState) {
        tabs = pane.tabs
        selectedTabID = pane.selectedTabID
    }

    public func restoredPane(side: PaneSide, fallbackURL: URL) -> PaneState {
        guard !tabs.isEmpty else {
            return PaneState(side: side, initialURL: fallbackURL)
        }
        return PaneState(side: side, tabs: tabs, selectedTabID: selectedTabID)
    }
}

public struct DualPaneSessionSnapshot: Codable, Equatable, Sendable {
    public let left: PaneSessionSnapshot
    public let right: PaneSessionSnapshot

    public init(left: PaneState, right: PaneState) {
        self.left = PaneSessionSnapshot(pane: left)
        self.right = PaneSessionSnapshot(pane: right)
    }

    public func restoredPanes(fallbackURL: URL) -> (left: PaneState, right: PaneState) {
        (
            left: left.restoredPane(side: .left, fallbackURL: fallbackURL),
            right: right.restoredPane(side: .right, fallbackURL: fallbackURL)
        )
    }
}

public final class PaneSessionStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "paneSession") {
        self.defaults = defaults
        self.key = key
    }

    public func load(fallbackURL: URL) -> (left: PaneState, right: PaneState) {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(DualPaneSessionSnapshot.self, from: data)
        else {
            return (
                left: PaneState(side: .left, initialURL: fallbackURL),
                right: PaneState(side: .right, initialURL: fallbackURL)
            )
        }
        return snapshot.restoredPanes(fallbackURL: fallbackURL)
    }

    public func save(left: PaneState, right: PaneState) {
        let snapshot = DualPaneSessionSnapshot(left: left, right: right)
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }
}
