import SwiftUI

struct CPUCardView: View {
    @ObservedObject var engine: CPUStressEngine

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "cpu", tint: Accent.cpu, title: "CPU",
                           status: engine.statusText, active: engine.isRunning)

                HStack(spacing: 12) {
                    ControlLabel(text: "Cores")
                    Slider(
                        value: Binding(
                            get: { Double(engine.cores) },
                            set: { engine.cores = Int($0.rounded()) }
                        ),
                        in: 1...Double(engine.maxCores),
                        step: 1
                    )
                    .frame(maxWidth: 200)
                    .disabled(engine.isRunning)
                    Text("\(engine.cores)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 24, alignment: .trailing)

                    ControlLabel(text: "Workload")
                    Picker("", selection: $engine.workload) {
                        ForEach(CPUWorkload.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(engine.isRunning)
                }

                HStack(spacing: 12) {
                    ControlLabel(text: "Duration")
                    Picker("", selection: $engine.duration) {
                        ForEach(CPUDuration.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(engine.isRunning)

                    Spacer()
                    StressButtons(isRunning: engine.isRunning,
                                  start: engine.start, stop: engine.stop)
                }
            }
        }
    }
}
