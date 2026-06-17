import SwiftUI

/// Native Start / Stop button pair, shared by every resource card.
struct StressButtons: View {
    let isRunning: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button("Start", action: start)
                .buttonStyle(.borderedProminent)
                .tint(Accent.go)
                .disabled(isRunning)
            Button("Stop", action: stop)
                .buttonStyle(.bordered)
                .tint(Accent.stop)
                .disabled(!isRunning)
        }
        .controlSize(.large)
    }
}

/// A small grey caption used to label a control inline.
struct ControlLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}
