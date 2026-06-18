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

            BottomBar(cpu: model.cpu, gpu: model.gpu,
                      memory: model.memory, disk: model.disk,
                      startAll: model.startAll, stopAll: model.stopAll)
        }
        .background(VisualEffectView().ignoresSafeArea())
        .frame(minWidth: 720, minHeight: 820)
    }
}

/// Bottom action bar: a single toggle that runs every test while idle and
/// stops every running test once anything is active.
private struct BottomBar: View {
    @ObservedObject var cpu: CPUStressEngine
    @ObservedObject var gpu: GPUStressEngine
    @ObservedObject var memory: MemoryStressEngine
    @ObservedObject var disk: DiskStressEngine
    let startAll: () -> Void
    let stopAll: () -> Void

    private var anyRunning: Bool {
        cpu.isRunning || gpu.isRunning || memory.isRunning || disk.isRunning
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(anyRunning ? "Stop All" : "Run All Tests") {
                if anyRunning { stopAll() } else { startAll() }
            }
            .buttonStyle(.borderedProminent)
            .tint(anyRunning ? Accent.stop : Accent.cpu)
            .animation(.easeInOut(duration: 0.15), value: anyRunning)
            Spacer()
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
