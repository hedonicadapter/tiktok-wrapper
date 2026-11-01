import SwiftUI

/// Full-screen native overlay. Renders whatever kind it's given; the kind view calls `complete`
/// only once its unlock rule is satisfied. Skip appears after 30 s unless hardMode.
struct InterruptOverlay: View {
    let scheduled: ScheduledInterrupt
    let onComplete: (InterruptResult) -> Void

    @State private var skipAvailable = false
    private let skipAfter: TimeInterval = 30

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(scheduled.packTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    if !scheduled.hardMode && skipAvailable {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Skip") { onComplete(.skipped) }
                                .foregroundStyle(.secondary)
                        }
                    }
                }
        }
        .task {
            try? await Task.sleep(for: .seconds(skipAfter))
            skipAvailable = true
        }
    }

    @ViewBuilder
    private var content: some View {
        switch scheduled.interrupt {
        case let .quiz(q, answers, correct, explain):
            QuizView(question: q, answers: answers, correct: correct, explain: explain,
                     unlock: scheduled.unlock, onComplete: onComplete)
        case let .flashcard(front, back):
            FlashcardView(front: front, back: back, unlock: scheduled.unlock, onComplete: onComplete)
        case let .prompt(text, minChars):
            PromptView(text: text, minChars: minChars, onComplete: onComplete)
        case let .read(markdown, minSeconds):
            ReadView(markdown: markdown, minSeconds: minSeconds, onComplete: onComplete)
        case let .timer(label, seconds):
            TimerView(label: label, seconds: seconds, onComplete: onComplete)
        case let .web(url, unlockAfterSeconds):
            WebInterruptView(url: url, unlockAfterSeconds: unlockAfterSeconds,
                             hideSelectors: scheduled.hideSelectors, onComplete: onComplete)
        }
    }
}

/// Shared bottom button style for all kinds.
struct UnlockButton: View {
    let title: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!enabled)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }
}
