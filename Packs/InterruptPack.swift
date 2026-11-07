import Foundation

/// hide-selectors.json: CSS selectors to hide, and nag buttons to auto-click ("Not now").
struct NagSelectors: Codable, Equatable {
    var hide: [String] = []
    var click: [String] = []
}

// MARK: - Manifest (Documents/packs/<id>/manifest.json)

struct PackManifest: Codable {
    let id: String
    let title: String
    let kind: InterruptKind
    let items: String?              // file name of items array; default "items.json"
    let strategy: StrategyName?     // default sequential
    let unlock: UnlockRule?         // default per kind
    let hideSelectors: [String]?    // optional extra CSS hide list for `web` kind

    var itemsFile: String { items ?? "items.json" }
    var strategyName: StrategyName { strategy ?? .sequential }
    var unlockRule: UnlockRule {
        if let u = unlock { return u }
        switch kind {
        case .quiz, .flashcard: return .correct
        case .prompt, .read, .timer, .web: return .done
        }
    }
}

enum StrategyName: String, Codable {
    case sequential
    case random
    case weightedWrong = "weighted-wrong"
    case spaced
}

// MARK: - Items

/// One raw item from items.json. Shape depends on manifest.kind; all fields optional,
/// validated at load time. `id` optional; defaults to index.
struct PackItem: Codable {
    var id: String?
    // quiz
    var q: String?
    var answers: [String]?
    var correct: Int?
    var explain: String?
    var image: String?          // file in pack folder, e.g. "signs/B2.png"
    // flashcard
    var front: String?
    var back: String?
    // prompt
    var text: String?
    var minChars: Int?
    // read
    var markdown: String?
    var file: String?           // alternative to inline markdown
    var minSeconds: Int?
    // timer
    var label: String?
    var seconds: Int?
    // web
    var url: String?
    var unlockAfterSeconds: Int?

    /// Converts to an Interrupt of the given kind, or throws with a reason.
    func toInterrupt(kind: InterruptKind, packDir: URL) throws -> Interrupt {
        switch kind {
        case .quiz:
            guard let q, let answers, let correct else { throw PackError.invalidItem("quiz needs q, answers, correct") }
            guard answers.count >= 2 else { throw PackError.invalidItem("quiz needs >= 2 answers") }
            guard answers.indices.contains(correct) else { throw PackError.invalidItem("quiz correct index out of range") }
            var imagePath: String? = nil
            if let image, !image.isEmpty {
                let u = packDir.appendingPathComponent(image)
                imagePath = FileManager.default.fileExists(atPath: u.path) ? u.path : nil
            }
            return .quiz(q: q, answers: answers, correct: correct, explain: explain, image: imagePath)
        case .flashcard:
            guard let front, let back else { throw PackError.invalidItem("flashcard needs front, back") }
            return .flashcard(front: front, back: back)
        case .prompt:
            guard let text else { throw PackError.invalidItem("prompt needs text") }
            return .prompt(text: text, minChars: max(1, minChars ?? 40))
        case .read:
            var md = markdown
            if md == nil, let file {
                let u = packDir.appendingPathComponent(file)
                md = try? String(contentsOf: u, encoding: .utf8)
            }
            guard let md, !md.isEmpty else { throw PackError.invalidItem("read needs markdown or readable file") }
            return .read(markdown: md, minSeconds: max(0, minSeconds ?? 20))
        case .timer:
            guard let seconds, seconds > 0 else { throw PackError.invalidItem("timer needs seconds > 0") }
            return .timer(label: label ?? "Take a break", seconds: seconds)
        case .web:
            guard let url, let u = URL(string: url), u.scheme != nil else { throw PackError.invalidItem("web needs valid url") }
            return .web(url: u, unlockAfterSeconds: max(0, unlockAfterSeconds ?? 60))
        }
    }
}

enum PackError: Error, CustomStringConvertible {
    case missingManifest(String)
    case badManifest(String, String)
    case missingItems(String, String)
    case badItems(String, String)
    case invalidItem(String)
    case empty(String)

    var description: String {
        switch self {
        case .missingManifest(let p): return "\(p): manifest.json missing"
        case .badManifest(let p, let e): return "\(p): bad manifest: \(e)"
        case .missingItems(let p, let f): return "\(p): items file '\(f)' missing"
        case .badItems(let p, let e): return "\(p): bad items: \(e)"
        case .invalidItem(let e): return "invalid item: \(e)"
        case .empty(let p): return "\(p): no valid items"
        }
    }
}

// MARK: - Progress (persisted per pack)

struct ItemStats: Codable, Equatable {
    var shown = 0
    var correct = 0
    var wrong = 0
    var correctStreak = 0
    var lastShown: Date?
    // spaced (SM-2 lite)
    var easiness = 2.5
    var intervalDays = 0.0
    var dueAt: Date?
}

struct PackProgress: Codable, Equatable {
    var items: [String: ItemStats] = [:]
    var cursor = 0                  // sequential strategy position
    var lastItemId: String?

    func stats(for id: String) -> ItemStats { items[id] ?? ItemStats() }
}

// MARK: - Pack

/// Loaded, validated pack. `next` picks via strategy; `record` updates progress.
protocol InterruptPack: AnyObject {
    var id: String { get }
    var title: String { get }
    var kind: InterruptKind { get }
    var unlock: UnlockRule { get }
    var itemCount: Int { get }
    func next(progress: PackProgress) -> (itemId: String, interrupt: Interrupt)?
    func record(itemId: String, result: InterruptResult, progress: inout PackProgress)
}

final class LoadedPack: InterruptPack {
    let id: String
    let title: String
    let kind: InterruptKind
    let unlock: UnlockRule
    let directory: URL
    let hideSelectors: [String]
    private let items: [(id: String, interrupt: Interrupt)]
    private let strategy: ItemStrategy

    var itemCount: Int { items.count }
    var itemIds: [String] { items.map(\.id) }

    init(manifest: PackManifest, items: [(id: String, interrupt: Interrupt)], directory: URL) {
        self.id = manifest.id
        self.title = manifest.title
        self.kind = manifest.kind
        self.unlock = manifest.unlockRule
        self.directory = directory
        self.hideSelectors = manifest.hideSelectors ?? []
        self.items = items
        self.strategy = makeStrategy(manifest.strategyName)
    }

    func next(progress: PackProgress) -> (itemId: String, interrupt: Interrupt)? {
        guard !items.isEmpty else { return nil }
        let idx = strategy.pick(itemIds: items.map(\.id), progress: progress)
        let item = items[min(max(idx, 0), items.count - 1)]
        return (item.id, item.interrupt)
    }

    func record(itemId: String, result: InterruptResult, progress: inout PackProgress) {
        var s = progress.stats(for: itemId)
        s.shown += 1
        s.lastShown = Date()
        switch result {
        case .correct:
            s.correct += 1
            s.correctStreak += 1
        case .wrong:
            s.wrong += 1
            s.correctStreak = 0
        case .done:
            s.correct += 1
            s.correctStreak += 1
        case .skipped:
            s.correctStreak = 0
        }
        strategy.update(stats: &s, result: result)
        progress.items[itemId] = s
        progress.lastItemId = itemId
        if let i = items.firstIndex(where: { $0.id == itemId }) {
            progress.cursor = (i + 1) % items.count
        }
    }
}
