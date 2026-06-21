import Foundation
import Testing
@testable import DualFinderApp

@Suite("BatchRenameHistoryStore")
struct BatchRenameHistoryStoreTests {
    @Test("keeps most recent twenty values")
    func keepsMostRecentTwentyValues() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BatchRenameHistoryStore(defaults: defaults)

        for index in 1...25 {
            _ = store.record("value-\(index)", for: .find)
        }

        let values = store.values(for: .find)
        #expect(values.count == 20)
        #expect(values.first == "value-25")
        #expect(values.last == "value-6")
    }

    @Test("moves repeated values to front and persists")
    func movesRepeatedValuesToFrontAndPersists() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BatchRenameHistoryStore(defaults: defaults)

        _ = store.record("alpha", for: .replace)
        _ = store.record("beta", for: .replace)
        _ = store.record("alpha", for: .replace)

        let restored = BatchRenameHistoryStore(defaults: defaults)
        #expect(restored.values(for: .replace) == ["alpha", "beta"])
    }

    @Test("deletes a single value")
    func deletesSingleValue() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = BatchRenameHistoryStore(defaults: defaults)

        _ = store.record("alpha", for: .find)
        _ = store.record("beta", for: .find)
        let values = store.remove("alpha", for: .find)

        #expect(values == ["beta"])
        #expect(store.values(for: .find) == ["beta"])
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "BatchRenameHistoryStoreTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
