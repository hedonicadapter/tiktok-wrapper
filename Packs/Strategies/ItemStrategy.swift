import Foundation

/// Picks the index of the next item, or nil when the pack has nothing left to show.
/// Pure over (ids, progress) so it's testable.
protocol ItemStrategy {
    func pick(itemIds: [String], progress: PackProgress) -> Int?
    /// Hook for strategies that keep per-item scheduling state. `turn` = pack interrupts served so far.
    func update(stats: inout ItemStats, result: InterruptResult, turn: Int)
}

extension ItemStrategy {
    func update(stats: inout ItemStats, result: InterruptResult, turn: Int) {}
}

func makeStrategy(_ name: StrategyName, masteryStreak: Int = 3) -> ItemStrategy {
    switch name {
    case .sequential: return SequentialStrategy()
    case .random: return RandomStrategy()
    case .weightedWrong, .mastery: return MasteryStrategy(masteryStreak: masteryStreak)
    case .spaced: return SpacedStrategy()
    }
}

/// Avoids showing the same item twice in a row when there's a choice.
func avoidingRepeat(_ idx: Int, itemIds: [String], progress: PackProgress, fallback: () -> Int) -> Int {
    guard itemIds.count > 1, let last = progress.lastItemId, itemIds[idx] == last else { return idx }
    for _ in 0..<8 {
        let alt = fallback()
        if itemIds[alt] != last { return alt }
    }
    return (idx + 1) % itemIds.count
}
