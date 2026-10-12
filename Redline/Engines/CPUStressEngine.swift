import Foundation
import Darwin

/// Saturates the CPU with N worker threads running float / integer / mixed math.
final class CPUStressEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var cores: Int
    @Published var workload: CPUWorkload = .mixed
    @Published var duration: CPUDuration = .unlimited
    @Published private(set) var statusText = "Idle"

    let maxCores: Int
    private let log: ActivityLog
    private var stopFlag: AtomicFlag?
    private var threads: [Thread] = []
    private var autoStop: DispatchWorkItem?

    init(maxCores: Int, log: ActivityLog) {
        self.maxCores = maxCores
        self.cores = maxCores
        self.log = log
    }

    func start() {
        guard !isRunning else { return }
        let stopFlag = AtomicFlag()
        self.stopFlag = stopFlag
        let count = max(1, min(cores, maxCores))
        let mode = workload

        threads = (0..<count).map { _ in
            let thread = Thread { [stopFlag] in
                CPUStressEngine.run(mode: mode, stop: stopFlag)
            }
            thread.qualityOfService = .userInitiated
            return thread
        }
        threads.forEach { $0.start() }

        isRunning = true
        statusText = "\(count) cores · \(mode.rawValue)"
        log.log("CPU: \(count) cores, \(mode.rawValue)")

        if let seconds = duration.seconds {
            let work = DispatchWorkItem { [weak self] in self?.stop() }
            autoStop = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds), execute: work)
            log.log("CPU: auto-stop in \(duration.rawValue)")
        }
    }

    func stop() {
        guard isRunning else { return }
        autoStop?.cancel()
        autoStop = nil
        stopFlag?.set()
        stopFlag = nil
        threads.removeAll()
        isRunning = false
        statusText = "Idle"
        log.log("CPU: stopped")
    }

    private static func run(mode: CPUWorkload, stop: AtomicFlag) {
        var x = 1.5
        var n: UInt64 = 0x9E3779B97F4A7C15
        while !stop.isSet {
            switch mode {
            case .float:
                for _ in 0..<50_000 {
                    x = sin(x) * cos(x) + (abs(x) + 1).squareRoot()
                    x = Darwin.log(abs(x) + 1) + atan2(x, 1)
                    x = exp(min(abs(x), 10)) - exp(min(abs(x), 9))
                    if abs(x) > 1e15 { x = 1.5 }
                }
            case .integer:
                for _ in 0..<50_000 {
                    n = n &* 6364136223846793005 &+ 1442695040888963407
                    n ^= n >> 33
                    n = n &* 0xFF51AFD7ED558CCD
                    n ^= n >> 33
                    n = n &* 0xC4CEB9FE1A85EC53
                }
            case .mixed:
                for _ in 0..<25_000 {
                    x = sin(x) * cos(x) + (abs(x) + 1).squareRoot()
                    n = n &* 6364136223846793005 &+ 1
                    x += Double(n & 0xFFFF) / 65536.0
                    n ^= n >> 33
                    if abs(x) > 1e15 { x = 1.5 }
                }
            }
        }
        // Keep the optimiser from discarding the loop body.
        if x == .infinity && n == 0 { print(x, n) }
    }
}
