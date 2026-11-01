import Foundation

struct RandomStrategy: ItemStrategy {
    var rng: () -> Int = { Int.random(in: 0..<Int.max) }

    func pick(itemIds: [String], progress: PackProgress) -> Int {
        guard !itemIds.isEmpty else { return 0 }
        let idx = rng() % itemIds.count
        return avoidingRepeat(idx, itemIds: itemIds, progress: progress) { rng() % itemIds.count }
    }
}
