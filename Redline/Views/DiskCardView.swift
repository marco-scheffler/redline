import SwiftUI

struct DiskCardView: View {
    @ObservedObject var engine: DiskStressEngine

    private let sizes = [256, 512, 1024, 4096]
    private func label(_ mb: Int) -> String {
        mb >= 1024 ? "\(mb / 1024) GB" : "\(mb)"
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(symbol: "internaldrive", tint: Accent.disk, title: "Disk I/O",
                           status: engine.statusText, active: engine.isRunning)

                HStack(spacing: 12) {
                    ControlLabel(text: "Size")
                    Picker("", selection: $engine.sizeMB) {
                        ForEach(sizes, id: \.self) { Text(label($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(engine.isRunning)

                    ControlLabel(text: "Mode")
                    Picker("", selection: $engine.mode) {
                        ForEach(DiskMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .disabled(engine.isRunning)

                    Spacer()
                    StressButtons(isRunning: engine.isRunning,
                                  start: engine.start, stop: engine.stop)
                }

                if engine.isRunning && engine.speedMBps > 0 {
                    Text(String(format: "%.0f MB/s", engine.speedMBps))
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Accent.disk)
                }
            }
        }
    }
}
