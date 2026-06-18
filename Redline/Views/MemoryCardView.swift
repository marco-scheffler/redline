import SwiftUI

struct MemoryCardView: View {
    @ObservedObject var engine: MemoryStressEngine

    private var options: [Int] {
        [1, 2, 4, 8, 16, 32].filter { $0 <= engine.maxGigabytes }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "memorychip", tint: Accent.memory, title: "Memory",
                           status: engine.statusText, active: engine.isRunning)

                HStack(spacing: 12) {
                    ControlLabel(text: "Allocate")
                    Picker("", selection: $engine.gigabytes) {
                        ForEach(options, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(engine.isRunning)
                    ControlLabel(text: "GB")

                    Spacer()
                    StressButtons(isRunning: engine.isRunning,
                                  start: engine.start, stop: engine.stop)
                }

                if engine.isRunning {
                    HStack(spacing: 10) {
                        ProgressView(value: engine.fraction)
                            .tint(Accent.memory)
                        Text("\(engine.allocatedMB) / \(engine.targetMB) MB")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
