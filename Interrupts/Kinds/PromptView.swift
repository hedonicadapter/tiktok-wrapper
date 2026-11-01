import SwiftUI

/// Type at least minChars (non-whitespace) to unlock.
struct PromptView: View {
    let text: String
    let minChars: Int
    let onComplete: (InterruptResult) -> Void

    @State private var input = ""
    @FocusState private var focused: Bool

    private var charCount: Int { input.filter { !$0.isWhitespace }.count }
    private var ready: Bool { charCount >= minChars }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(text)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)

            TextEditor(text: $input)
                .focused($focused)
                .scrollContentBackground(.hidden)
                .padding(12)
                .frame(minHeight: 160)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal)

            Text("\(charCount) / \(minChars)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(ready ? .green : .secondary)
                .padding(.horizontal)

            Spacer()

            UnlockButton(title: "Done", enabled: ready) { onComplete(.done) }
        }
        .padding(.top)
        .onAppear { focused = true }
    }
}
