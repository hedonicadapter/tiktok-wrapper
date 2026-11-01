import XCTest
@testable import ScrollGate

final class StrategyTests: XCTestCase {
    func testWeightedWrongWeights() {
        var s = ItemStats()
        XCTAssertEqual(WeightedWrongStrategy.weight(s), 1.0)
        s.wrong = 2
        XCTAssertEqual(WeightedWrongStrategy.weight(s), 5.0)
        s.wrong = 0; s.correctStreak = 4
        XCTAssertEqual(WeightedWrongStrategy.weight(s), 0.2) // floored
    }

    func testWeightedWrongPrefersWrongItems() {
        let ids = ["a", "b", "c"]
        var p = PackProgress()
        p.items["b"] = ItemStats(shown: 1, correct: 0, wrong: 3, correctStreak: 0)
        p.items["a"] = ItemStats(shown: 3, correct: 3, wrong: 0, correctStreak: 3)
        p.items["c"] = ItemStats(shown: 3, correct: 3, wrong: 0, correctStreak: 3)
        var hits = 0
        for _ in 0..<500 where WeightedWrongStrategy().pick(itemIds: ids, progress: p) == 1 { hits += 1 }
        // weights: a=0.2, b=7, c=0.2 → b ~95%
        XCTAssertGreaterThan(hits, 400)
    }

    func testSequentialWraps() {
        let ids = ["a", "b"]
        var p = PackProgress()
        XCTAssertEqual(SequentialStrategy().pick(itemIds: ids, progress: p), 0)
        p.cursor = 1
        XCTAssertEqual(SequentialStrategy().pick(itemIds: ids, progress: p), 1)
        p.cursor = 2
        XCTAssertEqual(SequentialStrategy().pick(itemIds: ids, progress: p), 0)
    }

    func testRandomAvoidsImmediateRepeat() {
        let ids = ["a", "b", "c"]
        var p = PackProgress()
        p.lastItemId = "a"
        for _ in 0..<200 {
            XCTAssertNotEqual(RandomStrategy().pick(itemIds: ids, progress: p), 0)
        }
    }
}

final class SwipeCounterTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let name = "tq.test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func testCountsUniqueOnly() {
        let c = SwipeCounter(defaults: freshDefaults())
        XCTAssertTrue(c.register("v1"))
        XCTAssertFalse(c.register("v1"))
        XCTAssertTrue(c.register("v2"))
        XCTAssertEqual(c.count, 2)
        XCTAssertTrue(c.shouldFire(interval: 2))
        c.reset()
        XCTAssertEqual(c.count, 0)
        XCTAssertEqual(c.total, 2)
    }

    func testPersists() {
        let d = freshDefaults()
        SwipeCounter(defaults: d).register("x")
        XCTAssertEqual(SwipeCounter(defaults: d).count, 1)
    }
}

final class SchedulerTests: XCTestCase {
    func testQuietHoursWrapMidnight() {
        let store = PackStore(documents: FileManager.default.temporaryDirectory)
        let s = Scheduler(store: store, defaults: UserDefaults(suiteName: "tq.test.sched")!)
        // default config: 23:00–07:00
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let at = { (h: Int) -> Date in cal.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: h))! }
        XCTAssertTrue(s.isQuiet(at: at(23), calendar: cal))
        XCTAssertTrue(s.isQuiet(at: at(3), calendar: cal))
        XCTAssertFalse(s.isQuiet(at: at(7), calendar: cal))
        XCTAssertFalse(s.isQuiet(at: at(12), calendar: cal))
    }

    func testManifestDefaults() throws {
        let json = #"{"id":"x","title":"X","kind":"timer"}"#.data(using: .utf8)!
        let m = try JSONDecoder().decode(PackManifest.self, from: json)
        XCTAssertEqual(m.itemsFile, "items.json")
        XCTAssertEqual(m.strategyName, .sequential)
        XCTAssertEqual(m.unlockRule, .done)
    }

    func testInterruptRoundTrip() throws {
        let s = ScheduledInterrupt(packId: "p", packTitle: "P", itemId: "i",
                                   interrupt: .quiz(q: "q", answers: ["a", "b"], correct: 1, explain: nil),
                                   unlock: .correct, hardMode: false, hideSelectors: ["#nag"])
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(ScheduledInterrupt.self, from: data)
        XCTAssertEqual(back, s)
    }
}
