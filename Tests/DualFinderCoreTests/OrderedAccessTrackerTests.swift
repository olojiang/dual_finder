import Foundation
import Testing
@testable import DualFinderCore

@Suite("OrderedAccessTracker")
struct OrderedAccessTrackerTests {
    @Test("touch appends new key as most recently used")
    func touchAppendsNewKey() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")
        tracker.touch("c")

        #expect(tracker.oldest == "a")
        #expect(tracker.count == 3)
    }

    @Test("touch moves existing key to most recently used")
    func touchMovesExistingKey() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")
        tracker.touch("c")
        tracker.touch("a")

        #expect(tracker.oldest == "b")
        #expect(tracker.count == 3)
    }

    @Test("removeOldest returns and removes least recently used")
    func removeOldestReturnsLRU() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")
        tracker.touch("c")

        #expect(tracker.removeOldest() == "a")
        #expect(tracker.count == 2)
        #expect(tracker.oldest == "b")
    }

    @Test("removeOldest returns nil when empty")
    func removeOldestReturnsNilWhenEmpty() {
        var tracker = OrderedAccessTracker<String>()
        #expect(tracker.removeOldest() == nil)
    }

    @Test("remove deletes a specific key")
    func removeSpecificKey() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")
        tracker.touch("c")

        tracker.remove("b")
        #expect(tracker.count == 2)
        #expect(tracker.oldest == "a")
    }

    @Test("remove non-existent key does nothing")
    func removeNonExistentKey() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.remove("x")
        #expect(tracker.count == 1)
    }

    @Test("contains checks key existence")
    func containsChecksKey() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")

        #expect(tracker.contains("a"))
        #expect(tracker.contains("b"))
        #expect(!tracker.contains("c"))
    }

    @Test("clear removes all keys")
    func clearRemovesAll() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")
        tracker.clear()
        #expect(tracker.count == 0)
        #expect(tracker.oldest == nil)
    }

    @Test("keys returns all keys in access order")
    func keysReturnsInAccessOrder() {
        var tracker = OrderedAccessTracker<String>()
        tracker.touch("a")
        tracker.touch("b")
        tracker.touch("c")
        tracker.touch("a")

        #expect(tracker.keys == ["b", "c", "a"])
    }
}
