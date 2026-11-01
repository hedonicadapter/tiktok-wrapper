import SwiftUI

/// Renders markdown paragraphs; unlocks after minSeconds.
struct ReadView: View {
    let markdown: String
    let minSeconds: Int
    let onComplete: (InterruptResult) -> Void

    @State private var remaining: Int

    init(markdown: String, minSeconds: Int, onComplete: @escaping (InterruptResult) -> Void) {
        self.markdown = markdown
        self.minSeconds = minSeconds
        self.onComplete = onComplete
        _remaining = State(initialValue: minSeconds)
    }

    private var blocks: [String] {
        markdown.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                        MarkdownBlock(text: block)
                    }
                }
                .padding()
            }
            UnlockButton(title: remaining > 0 ? "Keep reading… \(remaining)s" : "Done", enabled: remaining <= 0) {
                onComplete(.done)
            }
        }
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
        }
    }
}

/// Minimal block-level markdown: headings, bullets, paragraphs with inline markdown.
struct MarkdownBlock: View {
    let text: String

    var body: some View {
        if text.hasPrefix("# ") {
            Text(inline(String(text.dropFirst(2)))).font(.title2.weight(.bold))
        } else if text.hasPrefix("## ") {
            Text(inline(String(text.dropFirst(3)))).font(.title3.weight(.semibold))
        } else if text.hasPrefix("### ") {
            Text(inline(String(text.dropFirst(4)))).font(.headline)
        } else if text.hasPrefix("- ") || text.hasPrefix("* ") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(text.split(separator: "\n").enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 8) {
                        Text("•")
                        Text(inline(String(line.dropFirst(2))))
                    }
                }
            }
        } else {
            Text(inline(text)).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inline(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
