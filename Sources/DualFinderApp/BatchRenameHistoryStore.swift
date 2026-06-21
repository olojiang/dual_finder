import Foundation

struct BatchRenameHistoryStore {
    enum Field {
        case find
        case replace
    }

    private let defaults: UserDefaults
    private let keyPrefix: String
    private let limit: Int

    init(defaults: UserDefaults = .standard, keyPrefix: String = "batchRenameHistory", limit: Int = 20) {
        self.defaults = defaults
        self.keyPrefix = keyPrefix
        self.limit = limit
    }

    func values(for field: Field) -> [String] {
        defaults.stringArray(forKey: key(for: field)) ?? []
    }

    func record(_ value: String, for field: Field) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return values(for: field)
        }

        var next = values(for: field)
        next.removeAll { $0 == trimmed }
        next.insert(trimmed, at: 0)
        next = Array(next.prefix(limit))
        defaults.set(next, forKey: key(for: field))
        return next
    }

    func remove(_ value: String, for field: Field) -> [String] {
        let next = values(for: field).filter { $0 != value }
        defaults.set(next, forKey: key(for: field))
        return next
    }

    private func key(for field: Field) -> String {
        switch field {
        case .find:
            "\(keyPrefix).find"
        case .replace:
            "\(keyPrefix).replace"
        }
    }
}
