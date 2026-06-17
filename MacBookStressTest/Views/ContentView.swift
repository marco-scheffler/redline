import SwiftUI

struct ContentView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    HeaderView(info: model.info)
                    CPUCardView(engine: model.cpu)
                    GPUCardView(engine: model.gpu)
                    MemoryCardView(engine: model.memory)
                    DiskCardView(engine: model.disk)
                    MonitorCardView(monitor: model.monitor)
                    ActivityLogView(log: model.log)
                }
                .padding(20)
            }

            Divider()

            HStack(spacing: 10) {
                Button("Run All Tests", action: model.startAll)
                    .buttonStyle(.borderedProminent)
                    .tint(Accent.cpu)
                Button("Stop All", action: model.stopAll)
                    .buttonStyle(.bordered)
                    .tint(Accent.stop)
                Spacer()
            }
            .controlSize(.large)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .background(VisualEffectView().ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 820)
    }
}
