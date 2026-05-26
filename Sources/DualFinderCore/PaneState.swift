import Foundation

public enum PaneSide: String, Sendable {
    case left
    case right
}

public struct FileTab: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var url: URL

    public init(id: UUID = UUID(), url: URL) {
        self.id = id
        self.url = url
    }
}

public struct PaneState: Sendable {
    public let side: PaneSide
    public private(set) var tabs: [FileTab]
    public var selectedTabID: UUID
    public var selectedItemURLs: Set<URL>

    public init(side: PaneSide, initialURL: URL) {
        self.side = side
        let tab = FileTab(url: initialURL)
        tabs = [tab]
        selectedTabID = tab.id
        selectedItemURLs = []
    }

    public var selectedTab: FileTab? {
        tabs.first { $0.id == selectedTabID }
    }

    public var selectedURL: URL {
        selectedTab?.url ?? tabs[0].url
    }

    @discardableResult
    public mutating func addTab(url: URL) -> UUID {
        let tab = FileTab(url: url)
        tabs.append(tab)
        selectedTabID = tab.id
        selectedItemURLs.removeAll()
        return tab.id
    }

    public mutating func closeTab(id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
            selectedItemURLs.removeAll()
        }
    }

    public mutating func navigateSelectedTab(to url: URL) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        tabs[index].url = url
        selectedItemURLs.removeAll()
    }
}
