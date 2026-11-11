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
                                   interrupt: .quiz(q: "q", answers: ["a", "b"], correct: 1, explain: nil, image: nil),
                                   unlock: .correct, hardMode: false, hideSelectors: ["#nag"])
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(ScheduledInterrupt.self, from: data)
        XCTAssertEqual(back, s)
    }
}

final class PackStoreTests: XCTestCase {
    /// Repo's Resources/starter-packs, located relative to this file so it works in SwiftPM and Xcode.
    private var starterPacks: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/starter-packs")
    }

    private func makeStore() throws -> PackStore {
        let docs = FileManager.default.temporaryDirectory.appendingPathComponent("tq-\(UUID().uuidString)")
        let store = PackStore(documents: docs)
        try FileManager.default.createDirectory(at: store.packsDir, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: starterPacks.path) {
            try FileManager.default.copyItem(at: starterPacks.appendingPathComponent(name),
                                             to: store.packsDir.appendingPathComponent(name))
        }
        return store
    }

    func testStarterPacksLoad() throws {
        let store = try makeStore()
        store.reload()
        XCTAssertEqual(store.errors, [])
        XCTAssertEqual(store.packs.map(\.id).sorted(), ["blank-prompt", "drivers-ed", "stretch"])
        let de = try XCTUnwrap(store.pack(id: "drivers-ed"))
        XCTAssertEqual(de.kind, .quiz)
        XCTAssertEqual(de.itemCount, 10)
        XCTAssertEqual(de.unlock, .correct)
        XCTAssertEqual(store.pack(id: "stretch")?.kind, .timer)
        XCTAssertEqual(store.pack(id: "blank-prompt")?.kind, .prompt)
    }

    func testBrokenPackIsSkippedNotFatal() throws {
        let store = try makeStore()
        let bad = store.packsDir.appendingPathComponent("bad")
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try #"{"id":"bad","title":"Bad","kind":"quiz"}"#.write(to: bad.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try #"[{"q":"no answers"}]"#.write(to: bad.appendingPathComponent("items.json"), atomically: true, encoding: .utf8)
        store.reload()
        XCTAssertEqual(store.packs.count, 3)
        XCTAssertTrue(store.errors.contains { $0.contains("bad") })
    }

    func testSchedulerPicksAndRecords() throws {
        let store = try makeStore()
        store.reload()
        let defaults = UserDefaults(suiteName: "tq.test.\(UUID().uuidString)")!
        let sched = Scheduler(store: store, defaults: defaults)
        sched.reloadConfig()   // no config.json -> default weights
        var seenPacks = Set<String>()
        for _ in 0..<60 {
            let s = try XCTUnwrap(sched.nextInterrupt())
            seenPacks.insert(s.packId)
            sched.record(s, result: .wrong)
        }
        XCTAssertEqual(seenPacks, ["blank-prompt", "drivers-ed", "stretch"])
        let p = sched.loadProgress(packId: "drivers-ed")
        XCTAssertGreaterThan(p.items.values.reduce(0) { $0 + $1.wrong }, 0)
    }

    func testWrongAnswerRecursSoon() throws {
        let store = try makeStore()
        store.reload()
        let de = try XCTUnwrap(store.pack(id: "drivers-ed"))
        var within5 = 0
        for _ in 0..<50 {
            var progress = PackProgress()
            for id in de.itemIds { for _ in 0..<3 { de.record(itemId: id, result: .correct, progress: &progress) } }
            de.record(itemId: "stopplikt", result: .wrong, progress: &progress)
            // Simulate following interrupts: answer everything else right until stopplikt comes back.
            var steps = 0
            while steps < 20 {
                steps += 1
                let picked = try XCTUnwrap(de.next(progress: progress))
                if picked.itemId == "stopplikt" { break }
                de.record(itemId: picked.itemId, result: .correct, progress: &progress)
            }
            if steps <= 5 { within5 += 1 }
        }
        // weight 3 vs nine others at 0.2 → ~62% per draw after the no-immediate-repeat draw
        XCTAssertGreaterThan(within5, 40)
    }
}

final class MasteryTests: XCTestCase {
    private let ids = ["a", "b", "c", "d", "e", "f"]

    /// Serve one turn: pick, record result via the strategy like LoadedPack does.
    private func serve(_ m: MasteryStrategy, _ p: inout PackProgress, answer: (String) -> InterruptResult) -> String? {
        guard let i = m.pick(itemIds: ids, progress: p) else { return nil }
        let id = ids[i]
        var s = p.stats(for: id)
        let r = answer(id)
        s.shown += 1
        switch r { case .correct, .done: s.correctStreak += 1; case .wrong, .skipped: s.correctStreak = 0 }
        p.served = p.turn + 1
        m.update(stats: &s, result: r, turn: p.turn)
        p.items[id] = s
        p.lastItemId = id
        return id
    }

    func testWrongComesBackAfterTwoOthers() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress()
        let first = serve(m, &p) { _ in .wrong }!
        let next3 = (0..<3).map { _ in serve(m, &p) { _ in .correct }! }
        XCTAssertNotEqual(next3[0], first)
        XCTAssertNotEqual(next3[1], first)
        XCTAssertEqual(next3[2], first, "wrong item due again on the third turn")
    }

    func testRetiresAfterStreakAndNeverReturns() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress()
        // Everything wrong once, then always right: each needs 3 rights in a row.
        var seen = Set<String>()
        for _ in 0..<400 {
            guard let id = serve(m, &p, answer: { id in seen.insert(id).inserted ? .wrong : .correct }) else { break }
            _ = id
        }
        for id in ids { XCTAssertEqual(p.items[id]?.retired, true, id); XCTAssertEqual(p.items[id]?.correctStreak, 3) }
        XCTAssertNil(m.pick(itemIds: ids, progress: p), "all retired: pack has nothing left")
    }

    func testRightOnFirstSightNeedsOneConfirmation() {
        let m = MasteryStrategy(random: { _ in 0 })
        var s = ItemStats(); s.shown = 1; s.correctStreak = 1
        m.update(stats: &s, result: .correct, turn: 1)
        XCTAssertEqual(s.correctStreak, 2); XCTAssertEqual(s.retired, false); XCTAssertEqual(s.dueTurn, 26)
        s.shown = 2; s.correctStreak = 3
        m.update(stats: &s, result: .correct, turn: 26)
        XCTAssertEqual(s.retired, true)
    }

    func testWrongResetsStreakAndUnretires() {
        let m = MasteryStrategy()
        var s = ItemStats(); s.shown = 5; s.correctStreak = 0; s.retired = true
        m.update(stats: &s, result: .wrong, turn: 10)
        XCTAssertEqual(s.retired, false); XCTAssertEqual(s.dueTurn, 12)
    }

    func testDoesNotRepeatLastWhenOthersExist() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress()
        p.served = 5
        p.items["a"] = ItemStats(shown: 1, correct: 0, wrong: 1, correctStreak: 0, dueTurn: 3)
        p.lastItemId = "a"
        XCTAssertNotEqual(m.pick(itemIds: ids, progress: p), 0)
    }
}

final class MasteryMixingTests: XCTestCase {
    private let ids = ["a", "b", "c", "d", "e", "f"]

    func testWrongBeatsEverything() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress(); p.served = 10
        p.items["c"] = ItemStats(shown: 1, correct: 0, wrong: 1, correctStreak: 0, dueTurn: 9)
        p.items["b"] = ItemStats(shown: 2, correct: 2, wrong: 0, correctStreak: 1, dueTurn: 5)
        XCTAssertEqual(m.pick(itemIds: ids, progress: p), 2, "overdue wrong item first")
    }

    func testReviewsAlternateWithNewItems() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress()
        for id in ["a", "b", "c"] { p.items[id] = ItemStats(shown: 2, correct: 2, wrong: 0, correctStreak: 1, dueTurn: 0) }
        p.served = 4   // even turn → new item
        XCTAssertEqual(m.pick(itemIds: ids, progress: p), 3, "even turn: unseen")
        p.served = 5   // odd turn → due review
        XCTAssertEqual(m.pick(itemIds: ids, progress: p), 0, "odd turn: review")
    }

    func testLegacyProgressWithoutDueTurnStillServed() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress(); p.served = 1
        for id in ids { p.items[id] = ItemStats(shown: 1, correct: 1, wrong: 0, correctStreak: 1) }
        XCTAssertNotNil(m.pick(itemIds: ids, progress: p))
    }

    func testOnlyLastItemLeftIsStillShown() {
        let m = MasteryStrategy(random: { _ in 0 })
        var p = PackProgress(); p.served = 3; p.lastItemId = "a"
        for id in ids { var s = ItemStats(); s.shown = 3; s.retired = (id != "a"); p.items[id] = s }
        p.items["a"]?.dueTurn = 10
        XCTAssertEqual(m.pick(itemIds: ids, progress: p), 0)
    }
}

final class PackWeightTests: XCTestCase {
    func testUnlistedPacksDefaultToWeightOne() throws {
        let docs = FileManager.default.temporaryDirectory.appendingPathComponent("tq-w-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: docs, withIntermediateDirectories: true)
        try #"{"interval":5,"hardMode":false,"packs":{"drivers-ed":3,"stretch":0}}"#
            .write(to: docs.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let s = Scheduler(store: PackStore(documents: docs), defaults: UserDefaults(suiteName: "tq.test.\(UUID().uuidString)")!)
        s.reloadConfig()
        XCTAssertEqual(s.weight(for: "drivers-ed"), 3)
        XCTAssertEqual(s.weight(for: "stretch"), 0)
        XCTAssertEqual(s.weight(for: "korkort-emil"), 1)
    }
}
