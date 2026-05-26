import Foundation
import Testing
@testable import DualFinderCore

@Suite("FolderSortRuleStore")
struct FolderSortRuleStoreTests {
    @Test("stores sort rules independently by folder")
    func storesRulesByFolder() {
        let suiteName = "FolderSortRuleStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = FolderSortRuleStore(defaults: defaults)
        let first = URL(fileURLWithPath: "/tmp/first")
        let second = URL(fileURLWithPath: "/tmp/second")

        store.setRule(FileSortRule(field: .name, direction: .ascending), for: first)
        store.setRule(FileSortRule(field: .size, direction: .descending), for: second)

        #expect(store.rule(for: first) == FileSortRule(field: .name, direction: .ascending))
        #expect(store.rule(for: second) == FileSortRule(field: .size, direction: .descending))
        #expect(store.rule(for: URL(fileURLWithPath: "/tmp/other")) == FileSortRule())
    }
}
