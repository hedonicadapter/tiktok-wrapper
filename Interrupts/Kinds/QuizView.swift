import SwiftUI

/// unlock .correct: wrong answer shows explanation, re-asks. .anyAnswer: any pick unlocks after explanation.
struct QuizView: View {
    let question: String
    let answers: [String]
    let correct: Int
    let explain: String?
    var imagePath: String? = nil
    let unlock: UnlockRule
    let onComplete: (InterruptResult) -> Void

    @State private var picked: Int?
    @State private var wrongCount = 0
    @State private var locked = false   // after pick, until Continue/Try again

    private var pickedCorrect: Bool { picked == correct }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let imagePath, let ui = UIImage(contentsOfFile: imagePath) {
                        Image(uiImage: ui)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 220)
                            .padding(.vertical, 4)
                    }
                    Text(question)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 10) {
                        ForEach(answers.indices, id: \.self) { i in
                            Button { choose(i) } label: {
                                HStack {
                                    Text(answers[i]).multilineTextAlignment(.leading)
                                    Spacer()
                                    icon(for: i)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(background(for: i), in: RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(locked)
                        }
                    }

                    if locked, let explain, !explain.isEmpty {
                        Text(explain)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding()
            }

            // Correct (or any answer when allowed) completes in place; the card's swipe continues.
            if locked && !pickedCorrect && unlock != .anyAnswer {
                UnlockButton(title: "Try again", enabled: true) {
                    picked = nil
                    locked = false
                }
            }
        }
    }

    private func choose(_ i: Int) {
        picked = i
        locked = true
        if i != correct { wrongCount += 1 }
        if i == correct { onComplete(wrongCount == 0 ? .correct : .wrong) }
        else if unlock == .anyAnswer { onComplete(.wrong) }
    }

    @ViewBuilder
    private func icon(for i: Int) -> some View {
        if locked, i == picked {
            Image(systemName: pickedCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(pickedCorrect ? .green : .red)
        } else if locked, i == correct, unlock == .anyAnswer {
            Image(systemName: "checkmark.circle").foregroundStyle(.green)
        }
    }

    private func background(for i: Int) -> some ShapeStyle {
        if locked, i == picked {
            return AnyShapeStyle(pickedCorrect ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
        }
        return AnyShapeStyle(.quaternary)
    }
}
