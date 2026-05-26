import Foundation

public final class FolderSortRuleStore {
    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "folderSortRules") {
        self.defaults = defaults
        self.key = key
    }

    public func rule(for folder: URL) -> FileSortRule {
        allRules()[normalizedPath(for: folder)] ?? FileSortRule()
    }

    public func setRule(_ rule: FileSortRule, for folder: URL) {
        var rules = allRules()
        rules[normalizedPath(for: folder)] = rule
        if let data = try? JSONEncoder().encode(rules) {
            defaults.set(data, forKey: key)
        }
    }

    private func allRules() -> [String: FileSortRule] {
        guard let data = defaults.data(forKey: key),
              let rules = try? JSONDecoder().decode([String: FileSortRule].self, from: data)
        else {
            return [:]
        }
        return rules
    }

    private func normalizedPath(for folder: URL) -> String {
        folder.standardizedFileURL.path
    }
}
