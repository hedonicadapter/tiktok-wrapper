import Foundation

/// Leitner-style queue measured in this pack's interrupts ("turns"):
/// - wrong: due again after `wrongGap` turns, streak reset
/// - right: streak + 1, due again after a growing gap (4, 12, 36…)
/// - right on first sight: counts as already known (streak = masteryStreak - 1),
///   one confirmation later retires it
/// - streak reaches `masteryStreak`: retired, never shown again
/// Picking: most overdue first, else an unseen item, else the one due soonest.
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
        var overdue: (idx: Int, due: Int)?
        var soonest: (idx: Int, due: Int)?
        var unseen: [Int] = []
        for (i, id) in itemIds.enumerated() {
            guard let s = progress.items[id] else { unseen.append(i); continue }
            if s.retired == true { continue }
            let due = s.dueTurn ?? now
            if due <= now {
                if overdue == nil || due < overdue!.due { overdue = (i, due) }
            } else if soonest == nil || due < soonest!.due {
                soonest = (i, due)
            }
        }
        let last = progress.lastItemId
        // Don't repeat the item just shown if anything else is available.
        if let o = overdue, itemIds[o.idx] != last || (unseen.isEmpty && soonest == nil) { return o.idx }
        if !unseen.isEmpty {
            return unseen[random(unseen.count)]
        }
        if let o = overdue { return o.idx }
        return soonest?.idx
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
