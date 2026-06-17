import Foundation
import Darwin

/// Samples live system load (CPU per-core, memory, swap) ~1 Hz using Mach/sysctl.
/// Replaces the Python version's psutil dependency with native APIs.
final class SystemMonitor: ObservableObject {
    @Published private(set) var overallCPU: Double = 0          // 0…100
    @Published private(set) var perCoreCPU: [Double] = []        // 0…100 each
    @Published private(set) var memoryFraction: Double = 0       // 0…1
    @Published private(set) var memoryUsedBytes: UInt64 = 0
    @Published private(set) var swapFraction: Double = 0         // 0…1
    @Published private(set) var swapUsedBytes: UInt64 = 0

    let totalRAM: UInt64

    private var timer: Timer?
    private var previousTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []

    init(totalRAM: UInt64) {
        self.totalRAM = totalRAM
    }

    func start() {
        sampleCPU()  // prime the tick baseline
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.sample()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func sample() {
        sampleCPU()
        sampleMemory()
        sampleSwap()
    }

    // MARK: - CPU

    private func sampleCPU() {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else { return }
        defer {
            let address = vm_address_t(UInt(bitPattern: info))
            vm_deallocate(mach_task_self_, address,
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }

        let ticks = UnsafeBufferPointer(start: info, count: Int(infoCount))
        let stateMax = Int(CPU_STATE_MAX)
        var newTicks: [(UInt32, UInt32, UInt32, UInt32)] = []
        var perCore: [Double] = []
        var usedSum = 0.0
        var totalSum = 0.0

        for core in 0..<Int(cpuCount) {
            let base = core * stateMax
            let user = UInt32(bitPattern: ticks[base + Int(CPU_STATE_USER)])
            let system = UInt32(bitPattern: ticks[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(bitPattern: ticks[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(bitPattern: ticks[base + Int(CPU_STATE_NICE)])
            newTicks.append((user, system, idle, nice))

            if core < previousTicks.count {
                let prev = previousTicks[core]
                let used = Double(user &- prev.user) + Double(system &- prev.system) + Double(nice &- prev.nice)
                let total = used + Double(idle &- prev.idle)
                let pct = total > 0 ? (used / total) * 100.0 : 0
                perCore.append(pct)
                usedSum += used
                totalSum += total
            } else {
                perCore.append(0)
            }
        }
        previousTicks = newTicks
        let overall = totalSum > 0 ? (usedSum / totalSum) * 100.0 : 0

        DispatchQueue.main.async {
            self.perCoreCPU = perCore
            self.overallCPU = overall
        }
    }

    // MARK: - Memory

    private func sampleMemory() {
        var stats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = UInt64(vm_kernel_page_size)
        let active = UInt64(stats.active_count) * pageSize
        let wired = UInt64(stats.wire_count) * pageSize
        let compressed = UInt64(stats.compressor_page_count) * pageSize
        let used = active + wired + compressed
        let fraction = totalRAM > 0 ? min(1.0, Double(used) / Double(totalRAM)) : 0

        DispatchQueue.main.async {
            self.memoryUsedBytes = used
            self.memoryFraction = fraction
        }
    }

    // MARK: - Swap

    private func sampleSwap() {
        var usage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &usage, &size, nil, 0) == 0 else { return }
        let used = usage.xsu_used
        let total = usage.xsu_total
        let fraction = total > 0 ? min(1.0, Double(used) / Double(total)) : 0

        DispatchQueue.main.async {
            self.swapUsedBytes = used
            self.swapFraction = fraction
        }
    }
}
