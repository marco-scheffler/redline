import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 12) {
                    HeaderView(info: model.info)
                    CPUCardView(engine: model.cpu).accessibilityCard("cpu")
                    GPUCardView(engine: model.gpu).accessibilityCard("gpu")
                    MemoryCardView(engine: model.memory).accessibilityCard("memory")
                    DiskCardView(engine: model.disk).accessibilityCard("disk")
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

private extension View {
    /// Groups a card's controls under one identifier, so UI tests can tell
    /// the four identical Start buttons apart.
    func accessibilityCard(_ id: String) -> some View {
        accessibilityElement(children: .contain).accessibilityIdentifier(id)
    }
}

/// Bottom action bar: a single toggle that runs every test while idle and
/// stops every running test once anything is active.
private struct BottomBar: View {
    let cpu: CPUStressEngine
    let gpu: GPUStressEngine
    let memory: MemoryStressEngine
    let disk: DiskStressEngine
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
