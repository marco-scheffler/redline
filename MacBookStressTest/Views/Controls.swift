import SwiftUI

/// A single Start/Stop toggle button, shared by every resource card.
/// Shows a green "Start" while idle and a red "Stop" while running.
struct StressButtons: View {
    let isRunning: Bool
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        Button(isRunning ? "Stop" : "Start") {
            if isRunning { stop() } else { start() }
        }
        .buttonStyle(.borderedProminent)
        .tint(isRunning ? Accent.stop : Accent.go)
        .controlSize(.large)
        .frame(minWidth: 62)
        .animation(.easeInOut(duration: 0.15), value: isRunning)
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
