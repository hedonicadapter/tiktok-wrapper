import Foundation

/// Picks the index of the next item. Pure over (ids, progress) so it's testable.
protocol ItemStrategy {
    func pick(itemIds: [String], progress: PackProgress) -> Int
    /// Hook for strategies that keep per-item scheduling state (spaced).
    func update(stats: inout ItemStats, result: InterruptResult)
}

extension ItemStrategy {
    func update(stats: inout ItemStats, result: InterruptResult) {}
}

func makeStrategy(_ name: StrategyName) -> ItemStrategy {
    switch name {
    case .sequential: return SequentialStrategy()
    case .random: return RandomStrategy()
    case .weightedWrong: return WeightedWrongStrategy()
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
