import Foundation
import Metal

/// Drives the GPU with a heavy Metal compute kernel in a tight dispatch loop.
@MainActor @Observable
final class GPUStressEngine {
    private(set) var isRunning = false
    var bufferMB: Int = 256
    private(set) var iterationsPerSecond: Double = 0
    private(set) var gpuName: String = ""
    private(set) var statusText = "Idle"

    private let log: ActivityLog
    private var stopFlag: AtomicFlag?
    private var thread: Thread?

    init(log: ActivityLog) {
        self.log = log
    }

    func start() {
        guard !isRunning else { return }
        guard let device = MTLCreateSystemDefaultDevice() else {
            log.log("GPU: no Metal device found")
            return
        }
        let stopFlag = AtomicFlag()
        self.stopFlag = stopFlag
        isRunning = true
        gpuName = device.name
        statusText = "Starting…"
        log.log("GPU: starting (\(bufferMB) MB)…")

        let mb = bufferMB
        let thread = Thread { [weak self] in self?.run(device: device, bufferMB: mb, stop: stopFlag) }
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        stopFlag?.set()
        stopFlag = nil
        thread = nil
        isRunning = false
        iterationsPerSecond = 0
        statusText = "Idle"
        log.log("GPU: stopped")
    }

    nonisolated private func run(device: MTLDevice, bufferMB: Int, stop: AtomicFlag) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "stress"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            fail("GPU: pipeline setup failed", stop: stop)
            return
        }

        let elementCount = bufferMB * 1024 * 1024 / MemoryLayout<Float>.size
        guard let buffer = device.makeBuffer(length: elementCount * MemoryLayout<Float>.size,
                                             options: .storageModeShared) else {
            fail("GPU: buffer allocation failed", stop: stop)
            return
        }

        // Seed the buffer with varied values in -1…1, in slices so a stop is noticed quickly.
        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: elementCount)
        let slice = 1 << 20
        for sliceStart in stride(from: 0, to: elementCount, by: slice) {
            if stop.isSet { return }
            for i in sliceStart..<min(sliceStart + slice, elementCount) {
                pointer[i] = Float(i & 0xFFFF) / 32768 - 1
            }
        }

        stop.onMainUnlessSet {
            self.statusText = "\(bufferMB) MB buffer"
            self.log.log("GPU active: \(self.gpuName) (\(bufferMB) MB)")
        }

        let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let groupCount = (elementCount + threadsPerGroup - 1) / threadsPerGroup
        var iterations = 0
        var lastReport = Date()

        while !stop.isSet {
            guard let commandBuffer = queue.makeCommandBuffer(),
                  let encoder = commandBuffer.makeComputeCommandEncoder() else { continue }
            encoder.setComputePipelineState(pipeline)
            encoder.setBuffer(buffer, offset: 0, index: 0)
            encoder.dispatchThreadgroups(MTLSize(width: groupCount, height: 1, depth: 1),
                                         threadsPerThreadgroup: MTLSize(width: threadsPerGroup, height: 1, depth: 1))
            encoder.endEncoding()
            commandBuffer.commit()
            commandBuffer.waitUntilCompleted()

            iterations += 1
            let now = Date()
            if now.timeIntervalSince(lastReport) >= 1.0 {
                // Rate over the last interval, so thermal throttling shows up right away.
                let rate = Double(iterations) / now.timeIntervalSince(lastReport)
                iterations = 0
                lastReport = now
                stop.onMainUnlessSet {
                    self.iterationsPerSecond = rate
                    self.statusText = String(format: "%.1f iter/s · %d MB", rate, bufferMB)
                }
            }
        }
    }

    nonisolated private func fail(_ message: String, stop: AtomicFlag) {
        log.log(message)
        stop.onMainUnlessSet { self.isRunning = false; self.statusText = "Idle" }
    }
}
