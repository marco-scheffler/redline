import Foundation

/// Owns the system info, the four stress engines, the monitor and the log.
/// Created once and shared through the environment.
@MainActor @Observable
final class AppModel {
    let info = SystemInfo.current()
    let log = ActivityLog()
    let monitor: SystemMonitor
    let cpu: CPUStressEngine
    let gpu: GPUStressEngine
    let memory: MemoryStressEngine
    let disk: DiskStressEngine

    init() {
        monitor = SystemMonitor(totalRAM: info.totalRAM, log: log)
        cpu = CPUStressEngine(maxCores: info.logicalCores, log: log)
        gpu = GPUStressEngine(log: log)
        let maxGB = max(1, Int(Double(info.totalRAM) / 1_073_741_824 * 0.9))
        memory = MemoryStressEngine(maxGigabytes: maxGB, log: log)
        disk = DiskStressEngine(log: log)
        monitor.start()
    }

    func startAll() {
        log.log("=== Starting all ===")
        cpu.start()
        gpu.start()
        memory.start()
        disk.start()
    }

    func stopAll() {
        log.log("=== Stopping all ===")
        cpu.stop()
        gpu.stop()
        memory.stop()
        disk.stop()
    }
}
