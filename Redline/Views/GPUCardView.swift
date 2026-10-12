import SwiftUI

struct GPUCardView: View {
    @Bindable var engine: GPUStressEngine

    private let buffers = [64, 128, 256, 512, 1024]

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "cpu.fill", tint: Accent.gpu, title: "GPU · Metal",
                           status: engine.statusText, active: engine.isRunning)

                HStack(spacing: 12) {
                    ControlLabel(text: "Buffer")
                    Picker("", selection: $engine.bufferMB) {
                        ForEach(buffers, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(engine.isRunning)
                    ControlLabel(text: "MB")

                    Spacer()
                    StressButtons(isRunning: engine.isRunning,
                                  start: engine.start, stop: engine.stop)
                }
            }
        }
    }
}
