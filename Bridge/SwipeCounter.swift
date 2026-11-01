import Foundation

/// Counts unique videos seen since last interrupt. Persisted so relaunch doesn't reset progress toward N.
final class SwipeCounter: ObservableObject {
    @Published private(set) var count: Int
    @Published private(set) var total: Int

    private let defaults: UserDefaults
    private var seen: [String]      // ordered for bounded eviction
    private var seenSet: Set<String>
    private let maxSeen = 500

    private enum Key {
        static let count = "tq.swipe.count"
        static let total = "tq.swipe.total"
        static let seen = "tq.swipe.seen"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        count = defaults.integer(forKey: Key.count)
        total = defaults.integer(forKey: Key.total)
        seen = defaults.stringArray(forKey: Key.seen) ?? []
        seenSet = Set(seen)
    }

    /// Registers a video id. Returns true if it was new (counted).
    @discardableResult
    func register(_ id: String) -> Bool {
        guard !seenSet.contains(id) else { return false }
        seenSet.insert(id)
        seen.append(id)
        if seen.count > maxSeen {
            let evicted = seen.removeFirst()
            seenSet.remove(evicted)
        }
        count += 1
        total += 1
        persist()
        return true
    }

    func shouldFire(interval: Int) -> Bool {
        interval > 0 && count >= interval
    }

    func reset() {
        count = 0
        persist()
    }

    private func persist() {
        defaults.set(count, forKey: Key.count)
        defaults.set(total, forKey: Key.total)
        defaults.set(seen, forKey: Key.seen)
    }
}
