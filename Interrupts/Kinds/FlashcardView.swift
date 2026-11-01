import SwiftUI

/// Tap to reveal, then self-grade. unlock .correct: "Didn't know" re-hides and re-asks once more
/// (records wrong); .anyAnswer: either grade unlocks.
struct FlashcardView: View {
    let front: String
    let back: String
    let unlock: UnlockRule
    let onComplete: (InterruptResult) -> Void

    @State private var revealed = false
    @State private var missed = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            VStack(spacing: 16) {
                Text(revealed ? "Back" : "Front")
                    .font(.caption).foregroundStyle(.secondary)
                Text(revealed ? back : front)
                    .font(.title2.weight(.medium))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding()
            }
            .frame(maxWidth: .infinity, minHeight: 220)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal)
            .onTapGesture { withAnimation { revealed = true } }

            if !revealed {
                Text("Tap card to reveal").font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()

            if revealed {
                HStack(spacing: 12) {
                    Button {
                        if unlock == .anyAnswer {
                            onComplete(.wrong)
                        } else {
                            missed = true
                            withAnimation { revealed = false }
                        }
                    } label: {
                        Text("Didn't know").frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        onComplete(missed ? .wrong : .correct)
                    } label: {
                        Text("Knew it").frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(.headline)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }
}
