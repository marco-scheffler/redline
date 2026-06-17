import Foundation
import Metal

/// Drives the GPU with a heavy Metal compute kernel in a tight dispatch loop.
final class GPUStressEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var bufferMB: Int = 256
    @Published private(set) var iterationsPerSecond: Double = 0
    @Published private(set) var gpuName: String = ""
    @Published private(set) var statusText = "Idle"

    private let log: ActivityLog
    private let stopFlag = AtomicFlag()
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
        stopFlag.clear()
        isRunning = true
        gpuName = device.name
        statusText = "Starting…"
        log.log("GPU: starting (\(bufferMB) MB)…")

        let mb = bufferMB
        let thread = Thread { [weak self] in self?.run(device: device, bufferMB: mb) }
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        stopFlag.set()
        thread = nil
        isRunning = false
        iterationsPerSecond = 0
        statusText = "Idle"
        log.log("GPU: stopped")
    }

    private func run(device: MTLDevice, bufferMB: Int) {
        guard let queue = device.makeCommandQueue(),
              let library = device.makeDefaultLibrary(),
              let function = library.makeFunction(name: "stress"),
              let pipeline = try? device.makeComputePipelineState(function: function) else {
            log.log("GPU: pipeline setup failed")
            DispatchQueue.main.async { self.isRunning = false; self.statusText = "Idle" }
            return
        }

        let elementCount = bufferMB * 1024 * 1024 / MemoryLayout<Float>.size
        guard let buffer = device.makeBuffer(length: elementCount * MemoryLayout<Float>.size,
                                             options: .storageModeShared) else {
            log.log("GPU: buffer allocation failed")
            DispatchQueue.main.async { self.isRunning = false; self.statusText = "Idle" }
            return
        }

        let pointer = buffer.contents().bindMemory(to: Float.self, capacity: elementCount)
        for i in 0..<elementCount { pointer[i] = Float.random(in: -1...1) }

        DispatchQueue.main.async {
            self.statusText = "\(bufferMB) MB buffer"
            self.log.log("GPU active: \(self.gpuName) (\(bufferMB) MB)")
        }

        let threadsPerGroup = min(pipeline.maxTotalThreadsPerThreadgroup, 256)
        let groupCount = (elementCount + threadsPerGroup - 1) / threadsPerGroup
        let startTime = Date()
        var iterations = 0
        var lastReport = startTime

        while !stopFlag.isSet {
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
                let rate = Double(iterations) / now.timeIntervalSince(startTime)
                lastReport = now
                DispatchQueue.main.async {
                    self.iterationsPerSecond = rate
                    self.statusText = String(format: "%.1f iter/s · %d MB", rate, bufferMB)
                }
            }
        }
    }
}
