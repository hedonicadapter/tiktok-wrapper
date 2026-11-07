import Foundation

/// Fixed set of things the overlay knows how to render. Packs supply items of these kinds.
enum Interrupt: Codable, Equatable {
    case quiz(q: String, answers: [String], correct: Int, explain: String?, image: String?)   // image: absolute file path
    case flashcard(front: String, back: String)
    case prompt(text: String, minChars: Int)
    case read(markdown: String, minSeconds: Int)
    case timer(label: String, seconds: Int)
    case web(url: URL, unlockAfterSeconds: Int)

    var kind: InterruptKind {
        switch self {
        case .quiz: return .quiz
        case .flashcard: return .flashcard
        case .prompt: return .prompt
        case .read: return .read
        case .timer: return .timer
        case .web: return .web
        }
    }
}

enum InterruptKind: String, Codable, CaseIterable {
    case quiz, flashcard, prompt, read, timer, web
}

enum InterruptResult: String, Codable {
    case correct, wrong, done, skipped
}

/// How an interrupt is dismissed. Fixed list; packs pick one.
enum UnlockRule: String, Codable {
    case correct = "correct"        // quiz: must answer right; flashcard: must self-grade "knew it"
    case anyAnswer = "any-answer"   // quiz/flashcard: any answer dismisses
    case done = "done"              // prompt/read/timer/web: completion condition met
}

/// One scheduled interrupt: which pack and item it came from, what to show, how it unlocks.
/// Codable so a pending interrupt survives relaunch.
struct ScheduledInterrupt: Codable, Identifiable, Equatable {
    let id: UUID
    let packId: String
    let packTitle: String
    let itemId: String
    let interrupt: Interrupt
    let unlock: UnlockRule
    let hardMode: Bool
    let hideSelectors: [String]     // applied inside `web` kind only

    init(packId: String, packTitle: String, itemId: String, interrupt: Interrupt, unlock: UnlockRule,
         hardMode: Bool, hideSelectors: [String] = []) {
        self.id = UUID()
        self.packId = packId
        self.packTitle = packTitle
        self.itemId = itemId
        self.interrupt = interrupt
        self.unlock = unlock
        self.hardMode = hardMode
        self.hideSelectors = hideSelectors
    }
}
