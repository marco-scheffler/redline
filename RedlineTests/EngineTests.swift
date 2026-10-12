import Foundation
import Metal
import Testing
@testable import Redline

/// Exercises the stress engines and the monitor against the real hardware.
/// Serialized, because the engines compete for the same CPU, disk and threads.
@MainActor
@Suite(.serialized)
struct EngineTests {
    let log = ActivityLog()

    // MARK: - Stop flag

    @Test func updatesFromAStoppedRunAreDropped() async {
        let running = AtomicFlag()
        let stopped = AtomicFlag()
        stopped.set()
        var applied: [String] = []
        running.onMainUnlessSet { applied.append("running") }
        stopped.onMainUnlessSet { applied.append("stopped") }

        #expect(await waitUntil { !applied.isEmpty })
        try? await Task.sleep(for: .milliseconds(100))
        #expect(applied == ["running"])
    }

    // MARK: - CPU

    @Test func rapidStopStartLeavesNoWorkersBehind() async {
        let cpu = CPUStressEngine(maxCores: 4, log: log)
        let baseline = threadCount()

        for _ in 0..<20 {
            cpu.start()
            cpu.stop()
        }
        // Leaked workers only show while a newer run is active: a stop that reaches
        // a shared flag would end them together with the current run.
        cpu.start()
        try? await Task.sleep(for: .milliseconds(500))

        // 4 workers for the current run, plus slack for system threads.
        #expect(threadCount() - baseline <= 4 + 3)
        cpu.stop()
        #expect(!cpu.isRunning)
    }

    // MARK: - Disk

    @Test(arguments: DiskMode.allCases)
    func diskModeReportsThroughputAndCleansUp(mode: DiskMode) async {
        let disk = DiskStressEngine(log: log)
        disk.sizeMB = 64
        disk.mode = mode
        disk.start()
        #expect(disk.isRunning)

        #expect(await waitUntil(timeout: .seconds(20)) { disk.speedMBps > 0 })
        #expect(disk.isRunning)
        #expect(disk.speedMBps.isFinite)
        disk.stop()

        #expect(failures().isEmpty)
        #expect(tempFiles().isEmpty)
    }

    @Test func diskSurvivesStopStartWhilePreparing() async {
        let disk = DiskStressEngine(log: log)
        disk.sizeMB = 256
        disk.mode = .seqRead
        disk.start()
        disk.stop()
        disk.start()

        #expect(await waitUntil(timeout: .seconds(20)) { disk.speedMBps > 0 })
        #expect(disk.isRunning)
        disk.stop()
        #expect(failures().isEmpty)
    }

    // MARK: - Memory

    @Test func memoryAllocatesTheTargetAndReleasesIt() async {
        let memory = MemoryStressEngine(maxGigabytes: 1, log: log)
        memory.gigabytes = 1
        memory.start()

        #expect(await waitUntil(timeout: .seconds(20)) { memory.statusText == "1024 MB active" })
        #expect(memory.allocatedMB == 1024)
        #expect(memory.fraction == 1)

        memory.stop()
        #expect(!memory.isRunning)
        #expect(memory.allocatedMB == 0)
    }

    // MARK: - GPU

    @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil, "needs a Metal device"))
    func gpuReportsIterations() async {
        let gpu = GPUStressEngine(log: log)
        gpu.bufferMB = 64
        gpu.start()

        #expect(await waitUntil(timeout: .seconds(30)) { gpu.iterationsPerSecond > 0 })
        #expect(gpu.isRunning)
        gpu.stop()
        #expect(failures().isEmpty)
    }

    // MARK: - Monitor

    @Test func monitorReportsPlausibleValues() async {
        let info = SystemInfo.current()
        let monitor = SystemMonitor(totalRAM: info.totalRAM, log: log)
        monitor.start()
        defer { monitor.stop() }

        #expect(await waitUntil(timeout: .seconds(5)) { monitor.memoryUsedBytes > 0 })
        #expect(monitor.perCoreCPU.count == info.logicalCores)
        #expect((0...100).contains(monitor.overallCPU))
        #expect(monitor.memoryUsedBytes <= info.totalRAM)
        #expect((0...1).contains(monitor.swapFraction))
    }

    // MARK: - Helpers

    private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    private func failures() -> [String] {
        log.entries.map(\.message).filter {
            $0.contains("failed") || $0.contains("cannot") || $0.contains("not enough")
        }
    }

    private func tempFiles() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: NSTemporaryDirectory())) ?? []
        return names.filter { $0.hasPrefix("redline_disk") }
    }

    private func threadCount() -> Int {
        var threads: thread_act_array_t?
        var count: mach_msg_type_number_t = 0
        guard task_threads(mach_task_self_, &threads, &count) == KERN_SUCCESS, let threads else { return 0 }
        vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: threads)),
                      vm_size_t(Int(count) * MemoryLayout<thread_act_t>.stride))
        return Int(count)
    }
}
