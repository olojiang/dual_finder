import Foundation

public enum PaneSide: String, Codable, Sendable {
    case left
    case right
}

public struct FileTab: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var url: URL
    public var backHistory: [URL]
    public var forwardHistory: [URL]

    public init(id: UUID = UUID(), url: URL, backHistory: [URL] = [], forwardHistory: [URL] = []) {
        self.id = id
        self.url = url
        self.backHistory = backHistory
        self.forwardHistory = forwardHistory
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case url
        case backHistory
        case forwardHistory
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        url = try container.decode(URL.self, forKey: .url)
        backHistory = try container.decodeIfPresent([URL].self, forKey: .backHistory) ?? []
        forwardHistory = try container.decodeIfPresent([URL].self, forKey: .forwardHistory) ?? []
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

    public init(side: PaneSide, tabs: [FileTab], selectedTabID: UUID?) {
        precondition(!tabs.isEmpty, "PaneState requires at least one tab")
        self.side = side
        self.tabs = tabs
        if let selectedTabID, tabs.contains(where: { $0.id == selectedTabID }) {
            self.selectedTabID = selectedTabID
        } else {
            self.selectedTabID = tabs[0].id
        }
        selectedItemURLs = []
    }

    public var selectedTab: FileTab? {
        tabs.first { $0.id == selectedTabID }
    }

    public var selectedURL: URL {
        selectedTab?.url ?? tabs[0].url
    }

    public var canNavigateSelectedTabBack: Bool {
        !(selectedTab?.backHistory.isEmpty ?? true)
    }

    public var canNavigateSelectedTabForward: Bool {
        !(selectedTab?.forwardHistory.isEmpty ?? true)
    }

    public func tabID(atZeroBasedIndex index: Int) -> UUID? {
        guard tabs.indices.contains(index) else { return nil }
        return tabs[index].id
    }

    @discardableResult
    public mutating func addTab(url: URL) -> UUID {
        let tab = FileTab(url: url)
        tabs.append(tab)
        selectedTabID = tab.id
        selectedItemURLs.removeAll()
        return tab.id
    }

    @discardableResult
    public mutating func closeTab(id: UUID) -> Bool {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return false }
        tabs.remove(at: index)
        if selectedTabID == id {
            selectedTabID = tabs[min(index, tabs.count - 1)].id
            selectedItemURLs.removeAll()
        }
        return true
    }

    public mutating func navigateSelectedTab(to url: URL, selecting selection: URL? = nil) {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }) else { return }
        if tabs[index].url != url {
            tabs[index].backHistory.append(tabs[index].url)
            tabs[index].forwardHistory.removeAll()
        }
        tabs[index].url = url
        selectedItemURLs = selection.map { Set([$0]) } ?? []
    }

    @discardableResult
    public mutating func navigateSelectedTabBack() -> URL? {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
              let previousURL = tabs[index].backHistory.popLast()
        else {
            return nil
        }

        tabs[index].forwardHistory.append(tabs[index].url)
        tabs[index].url = previousURL
        selectedItemURLs.removeAll()
        return previousURL
    }

    @discardableResult
    public mutating func navigateSelectedTabForward() -> URL? {
        guard let index = tabs.firstIndex(where: { $0.id == selectedTabID }),
              let nextURL = tabs[index].forwardHistory.popLast()
        else {
            return nil
        }

        tabs[index].backHistory.append(tabs[index].url)
        tabs[index].url = nextURL
        selectedItemURLs.removeAll()
        return nextURL
    }
}
