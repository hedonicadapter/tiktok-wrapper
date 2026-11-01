import Foundation

/// SM-2 lite. Picks the most overdue item; unseen items first. Intervals in days,
/// but interrupts fire many times per day so anything not yet due falls back to weighted-wrong.
struct SpacedStrategy: ItemStrategy {
    func pick(itemIds: [String], progress: PackProgress) -> Int {
        guard !itemIds.isEmpty else { return 0 }
        let now = Date()
        // Unseen first
        if let i = itemIds.firstIndex(where: { progress.items[$0] == nil }) { return i }
        // Most overdue
        var best: (idx: Int, overdue: TimeInterval)?
        for (i, id) in itemIds.enumerated() {
            let s = progress.stats(for: id)
            let due = s.dueAt ?? now
            let overdue = now.timeIntervalSince(due)
            if overdue >= 0, best == nil || overdue > best!.overdue { best = (i, overdue) }
        }
        if let b = best {
            return avoidingRepeat(b.idx, itemIds: itemIds, progress: progress) { Int.random(in: 0..<itemIds.count) }
        }
        return WeightedWrongStrategy().pick(itemIds: itemIds, progress: progress)
    }

    func update(stats: inout ItemStats, result: InterruptResult) {
        switch result {
        case .correct, .done:
            if stats.intervalDays == 0 { stats.intervalDays = 1 }
            else if stats.intervalDays == 1 { stats.intervalDays = 6 }
            else { stats.intervalDays *= stats.easiness }
            stats.easiness = max(1.3, stats.easiness + 0.1)
        case .wrong:
            stats.intervalDays = 0
            stats.easiness = max(1.3, stats.easiness - 0.2)
        case .skipped:
            break
        }
        let seconds = max(600, stats.intervalDays * 86_400) // >= 10 min so it doesn't loop instantly
        stats.dueAt = Date().addingTimeInterval(seconds)
    }
}
