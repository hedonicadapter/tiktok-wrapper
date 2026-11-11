import Foundation

/// Leitner-style queue measured in this pack's interrupts ("turns"):
/// - wrong: due again after `wrongGap` turns, streak reset
/// - right: streak + 1, due again after a growing gap (4, 12, 36…)
/// - right on first sight: counts as already known (streak = masteryStreak - 1),
///   one confirmation later retires it
/// - streak reaches `masteryStreak`: retired, never shown again
/// Picking: overdue *wrong* items first (most overdue), then overdue reviews and unseen items
/// alternate turn by turn so new questions keep coming, else the item due soonest.
/// Returns nil once every item is retired.
struct MasteryStrategy: ItemStrategy {
    var masteryStreak = 3
    var wrongGap = 2
    var firstRightGap = 25
    var random: (Int) -> Int = { Int.random(in: 0..<$0) }

    func gap(afterStreak s: Int) -> Int {
        var g = 4
        for _ in 1..<max(1, s) { g *= 3 }
        return g
    }

    func pick(itemIds: [String], progress: PackProgress) -> Int? {
        let now = progress.turn
        let last = progress.lastItemId
        var wrongDue: (idx: Int, due: Int)?
        var reviewDue: (idx: Int, due: Int)?
        var soonest: (idx: Int, due: Int)?
        var unseen: [Int] = []
        func earlier(_ a: (idx: Int, due: Int)?, _ i: Int, _ due: Int) -> (idx: Int, due: Int) {
            guard let a else { return (i, due) }
            return due < a.due ? (i, due) : a
        }
        for (i, id) in itemIds.enumerated() {
            guard let s = progress.items[id] else { unseen.append(i); continue }
            if s.retired == true || id == last { continue }   // never the same item twice in a row
            let due = s.dueTurn ?? now                       // pre-mastery progress: due now
            if due <= now {
                if s.correctStreak == 0 { wrongDue = earlier(wrongDue, i, due) }
                else { reviewDue = earlier(reviewDue, i, due) }
            } else {
                soonest = earlier(soonest, i, due)
            }
        }
        if let w = wrongDue { return w.idx }
        switch (reviewDue, unseen.isEmpty) {
        case let (r?, false): return now % 2 == 0 ? unseen[random(unseen.count)] : r.idx
        case let (r?, true): return r.idx
        case (nil, false): return unseen[random(unseen.count)]
        case (nil, true): break
        }
        if let s = soonest { return s.idx }
        // Only the last-shown item is left.
        if let last, let i = itemIds.firstIndex(of: last), progress.items[last]?.retired != true { return i }
        return nil
    }

    func update(stats s: inout ItemStats, result: InterruptResult, turn: Int) {
        let firstSight = s.shown == 1
        switch result {
        case .correct, .done:
            if firstSight {
                s.correctStreak = max(1, masteryStreak - 1)
                s.dueTurn = turn + firstRightGap
            } else {
                s.dueTurn = turn + gap(afterStreak: s.correctStreak)
            }
        case .wrong:
            s.dueTurn = turn + wrongGap
        case .skipped:
            s.dueTurn = turn + wrongGap
        }
        // A wrong answer un-retires (only reachable via a card restored from before retirement).
        s.retired = s.correctStreak >= masteryStreak
    }
}
