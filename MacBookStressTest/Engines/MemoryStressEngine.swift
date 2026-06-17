import Foundation

/// Allocates a chosen amount of RAM and keeps touching it so it stays resident.
final class MemoryStressEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var gigabytes: Int = 4
    @Published private(set) var allocatedMB: Int = 0
    @Published private(set) var targetMB: Int = 0
    @Published private(set) var statusText = "Idle"

    let maxGigabytes: Int
    private let log: ActivityLog
    private let stopFlag = AtomicFlag()
    private var thread: Thread?

    init(maxGigabytes: Int, log: ActivityLog) {
        self.maxGigabytes = max(1, maxGigabytes)
        self.log = log
        self.gigabytes = min(4, self.maxGigabytes)
    }

    var fraction: Double {
        targetMB > 0 ? min(1.0, Double(allocatedMB) / Double(targetMB)) : 0
    }

    func start() {
        guard !isRunning else { return }
        stopFlag.clear()
        let gb = max(1, min(gigabytes, maxGigabytes))
        targetMB = gb * 1024
        allocatedMB = 0
        isRunning = true
        statusText = "Allocating \(gb) GB…"
        log.log("RAM: \(gb) GB")

        let target = targetMB
        let thread = Thread { [weak self] in self?.run(targetMB: target) }
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        stopFlag.set()
        thread = nil
        isRunning = false
        allocatedMB = 0
        targetMB = 0
        statusText = "Idle"
        log.log("RAM: released")
    }

    private func run(targetMB: Int) {
        let chunk = 64 * 1024 * 1024
        let targetBytes = targetMB * 1024 * 1024
        var blocks: [[UInt8]] = []
        var done = 0

        while !stopFlag.isSet && done < targetBytes {
            let size = min(chunk, targetBytes - done)
            var block = [UInt8](repeating: 0, count: size)
            for i in stride(from: 0, to: size, by: 4096) {
                block[i] = UInt8(i & 0xFF)
            }
            blocks.append(block)
            done += size
            let mb = done / (1024 * 1024)
            DispatchQueue.main.async { self.allocatedMB = mb }
            Thread.sleep(forTimeInterval: 0.03)
        }

        if !stopFlag.isSet {
            DispatchQueue.main.async { self.statusText = "\(self.allocatedMB) MB active" }
        }

        // Keep the pages hot until asked to stop.
        while !stopFlag.isSet {
            for index in blocks.indices {
                if stopFlag.isSet { break }
                for i in stride(from: 0, to: blocks[index].count, by: 4096) {
                    blocks[index][i] = blocks[index][i] &+ 1
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        blocks.removeAll()
    }
}
