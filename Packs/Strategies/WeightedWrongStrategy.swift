import Foundation

/// weight = 1 + 2*wrong - 0.5*correctStreak, floored at 0.2. Wrong answers recur soon.
struct WeightedWrongStrategy: ItemStrategy {
    var random: (Double) -> Double = { Double.random(in: 0..<$0) }

    static func weight(_ s: ItemStats) -> Double {
        max(0.2, 1.0 + 2.0 * Double(s.wrong) - 0.5 * Double(s.correctStreak))
    }

    func pick(itemIds: [String], progress: PackProgress) -> Int {
        guard !itemIds.isEmpty else { return 0 }
        let weights = itemIds.map { Self.weight(progress.stats(for: $0)) }
        let draw = { () -> Int in
            let total = weights.reduce(0, +)
            var r = random(total)
            for (i, w) in weights.enumerated() {
                r -= w
                if r < 0 { return i }
            }
            return weights.count - 1
        }
        return avoidingRepeat(draw(), itemIds: itemIds, progress: progress, fallback: draw)
    }
}
