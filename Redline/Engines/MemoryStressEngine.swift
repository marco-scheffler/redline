import Foundation
import Darwin

/// Allocates a chosen amount of RAM and keeps touching it so it stays resident.
@MainActor @Observable
final class MemoryStressEngine {
    private(set) var isRunning = false
    var gigabytes: Int = 4
    private(set) var allocatedMB: Int = 0
    private(set) var targetMB: Int = 0
    private(set) var statusText = "Idle"

    let maxGigabytes: Int
    private let log: ActivityLog
    private var stopFlag: AtomicFlag?
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
        let stopFlag = AtomicFlag()
        self.stopFlag = stopFlag
        let gb = max(1, min(gigabytes, maxGigabytes))
        targetMB = gb * 1024
        allocatedMB = 0
        isRunning = true
        statusText = "Allocating \(gb) GB…"
        log.log("RAM: \(gb) GB")

        let target = targetMB
        let thread = Thread { [weak self] in self?.run(targetMB: target, stop: stopFlag) }
        thread.qualityOfService = .utility
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        stopFlag?.set()
        stopFlag = nil
        thread = nil
        isRunning = false
        allocatedMB = 0
        targetMB = 0
        statusText = "Idle"
        log.log("RAM: released")
    }

    nonisolated private func run(targetMB: Int, stop: AtomicFlag) {
        let chunk = 64 * 1024 * 1024
        let targetBytes = targetMB * 1024 * 1024
        let pageSize = Int(getpagesize())
        var blocks: [[UInt8]] = []
        var done = 0

        while !stop.isSet && done < targetBytes {
            let size = min(chunk, targetBytes - done)
            // Random bytes defeat the memory compressor, so the pages really occupy RAM.
            let block = [UInt8](unsafeUninitializedCapacity: size) { buffer, count in
                arc4random_buf(buffer.baseAddress, size)
                count = size
            }
            blocks.append(block)
            done += size
            let mb = done / (1024 * 1024)
            stop.onMainUnlessSet { self.allocatedMB = mb }
            Thread.sleep(forTimeInterval: 0.03)
        }

        stop.onMainUnlessSet { self.statusText = "\(self.allocatedMB) MB active" }

        // Keep the pages hot until asked to stop.
        while !stop.isSet {
            for index in blocks.indices {
                if stop.isSet { break }
                for i in stride(from: 0, to: blocks[index].count, by: pageSize) {
                    blocks[index][i] = blocks[index][i] &+ 1
                }
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        blocks.removeAll()
    }
}
