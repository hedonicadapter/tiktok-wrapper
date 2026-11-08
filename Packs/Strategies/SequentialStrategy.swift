import Foundation

struct SequentialStrategy: ItemStrategy {
    func pick(itemIds: [String], progress: PackProgress) -> Int? {
        guard !itemIds.isEmpty else { return 0 }
        return progress.cursor % itemIds.count
    }
}
