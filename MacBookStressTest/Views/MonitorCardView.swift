import SwiftUI

struct MonitorCardView: View {
    @ObservedObject var monitor: SystemMonitor

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    IconTile(symbol: "gauge.with.dots.needle.bottom.50percent",
                             tint: Accent.monitor, active: false, size: 24)
                    Text("System Monitor").font(.system(size: 15, weight: .semibold))
                }

                MeterRow(label: "CPU", tint: .blue,
                         fraction: monitor.overallCPU / 100,
                         value: String(format: "%.0f %%", monitor.overallCPU))
                MeterRow(label: "Memory", tint: .purple,
                         fraction: monitor.memoryFraction,
                         value: "\(Int(monitor.memoryFraction * 100)) %  ·  \(bytes(monitor.memoryUsedBytes)) / \(bytes(monitor.totalRAM))")
                MeterRow(label: "Swap", tint: .orange,
                         fraction: monitor.swapFraction,
                         value: "\(Int(monitor.swapFraction * 100)) %  ·  \(bytes(monitor.swapUsedBytes))")

                if !monitor.perCoreCPU.isEmpty {
                    Text("Per-Core")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(Array(monitor.perCoreCPU.enumerated()), id: \.offset) { index, pct in
                            HStack(spacing: 5) {
                                Text("\(index)")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 16, alignment: .trailing)
                                ProgressView(value: min(1, pct / 100)).tint(.blue)
                                Text("\(Int(pct))")
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 22, alignment: .trailing)
                            }
                        }
                    }
                }
            }
        }
    }

    private func bytes(_ value: UInt64) -> String {
        let gb = Double(value) / 1_073_741_824
        return String(format: "%.1f GB", gb)
    }
}

private struct MeterRow: View {
    let label: String
    let tint: Color
    let fraction: Double
    let value: String

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .leading)
            Gauge(value: min(1, max(0, fraction))) { EmptyView() }
                .gaugeStyle(.accessoryLinearCapacity)
                .tint(tint)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(minWidth: 150, alignment: .trailing)
        }
    }
}
