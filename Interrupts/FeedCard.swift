import SwiftUI

/// Full-screen card that slides in like the next video. Wraps InterruptOverlay and adds the
/// "swipe up to continue" hint once the unlock rule is met.
struct FeedCard: View {
    let card: ScheduledInterrupt
    let phase: CardPhase
    let onComplete: (InterruptResult) -> Void

    private var completed: Bool {
        if case .completed = phase { return true }
        return false
    }

    private var icon: String {
        switch card.interrupt.kind {
        case .quiz: return "questionmark.circle"
        case .flashcard: return "rectangle.on.rectangle"
        case .prompt: return "pencil.line"
        case .read: return "book"
        case .timer: return "timer"
        case .web: return "globe"
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            if phase == .armed {
                // Teaser while the card waits below the screen; content (and its timers)
                // mounts only once the swipe commits.
                VStack(spacing: 12) {
                    Image(systemName: icon).font(.system(size: 44))
                    Text(card.packTitle).font(.title2.weight(.semibold))
                    Text("Swipe up").font(.footnote).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                InterruptOverlay(scheduled: card, onComplete: onComplete)
                    .allowsHitTesting(!completed)
                    .opacity(completed ? 0.35 : 1)
                    .animation(.easeOut(duration: 0.25), value: completed)
            }

            if completed {
                VStack(spacing: 6) {
                    Image(systemName: "chevron.up")
                        .font(.title2.weight(.semibold))
                    Text("Swipe up to continue")
                        .font(.footnote)
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 40)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .clipped()
    }
}
