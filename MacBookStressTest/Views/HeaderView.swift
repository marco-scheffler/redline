import SwiftUI

struct HeaderView: View {
    let info: SystemInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Stress Test")
                    .font(.system(size: 28, weight: .bold))
                Text("System-Belastungstest · CPU · GPU · Memory · Disk")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                InfoChip(text: info.shortCPU, tint: Accent.cpu)
                InfoChip(text: info.coresLabel, tint: Accent.go)
                InfoChip(text: info.ramLabel, tint: Accent.memory)
                InfoChip(text: "macOS \(info.osVersion)", tint: Accent.gpu)
            }

            Divider()
        }
    }
}
