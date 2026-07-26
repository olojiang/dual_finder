import Foundation

/// O(1) LRU access-order tracker using a doubly-linked list + dictionary.
/// Not thread-safe; callers must synchronize access.
public struct OrderedAccessTracker<Key: Hashable> {
    private final class Node {
        var key: Key
        var prev: Node?
        var next: Node?
        init(key: Key) { self.key = key }
    }

    private var nodes: [Key: Node] = [:]
    private var head: Node?
    private var tail: Node?

    public init() {}

    public var count: Int { nodes.count }

    public var oldest: Key? { head?.key }

    public var keys: [Key] {
        var result: [Key] = []
        var current = head
        while let node = current {
            result.append(node.key)
            current = node.next
        }
        return result
    }

    public func contains(_ key: Key) -> Bool {
        nodes[key] != nil
    }

    public mutating func touch(_ key: Key) {
        if let existing = nodes[key] {
            detach(existing)
            appendToTail(existing)
        } else {
            let node = Node(key: key)
            nodes[key] = node
            appendToTail(node)
        }
    }

    public mutating func remove(_ key: Key) {
        guard let node = nodes[key] else { return }
        detach(node)
        nodes.removeValue(forKey: key)
    }

    @discardableResult
    public mutating func removeOldest() -> Key? {
        guard let oldest = head else { return nil }
        let key = oldest.key
        detach(oldest)
        nodes.removeValue(forKey: key)
        return key
    }

    public mutating func clear() {
        nodes.removeAll()
        head = nil
        tail = nil
    }

    private mutating func detach(_ node: Node) {
        node.prev?.next = node.next
        node.next?.prev = node.prev
        if head === node { head = node.next }
        if tail === node { tail = node.prev }
        node.prev = nil
        node.next = nil
    }

    private mutating func appendToTail(_ node: Node) {
        node.prev = tail
        node.next = nil
        tail?.next = node
        tail = node
        if head == nil { head = node }
    }
}
