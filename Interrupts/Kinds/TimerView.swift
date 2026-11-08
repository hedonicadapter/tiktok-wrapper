import SwiftUI

/// Countdown. Unlocks at zero.
struct TimerView: View {
    let label: String
    let seconds: Int
    let onComplete: (InterruptResult) -> Void

    @State private var remaining: Int

    init(label: String, seconds: Int, onComplete: @escaping (InterruptResult) -> Void) {
        self.label = label
        self.seconds = seconds
        self.onComplete = onComplete
        _remaining = State(initialValue: seconds)
    }

    private var progress: Double { seconds > 0 ? 1 - Double(remaining) / Double(seconds) : 1 }

    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            Text(label)
                .font(.title3.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            ZStack {
                Circle().stroke(.quaternary, lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(.tint, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: progress)
                Text("\(remaining)")
                    .font(.system(size: 56, weight: .light, design: .rounded).monospacedDigit())
            }
            .frame(width: 200, height: 200)

            Spacer()
        }
        .task {
            while remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                remaining -= 1
            }
            onComplete(.done)
        }
    }
}
