import Foundation
import Darwin

/// Sequential / random read & write throughput test against a temp file,
/// bypassing the unified buffer cache with F_NOCACHE.
final class DiskStressEngine: ObservableObject {
    @Published private(set) var isRunning = false
    @Published var sizeMB: Int = 1024
    @Published var mode: DiskMode = .seqWrite
    @Published private(set) var speedMBps: Double = 0
    @Published private(set) var statusText = "Idle"

    private let log: ActivityLog
    private let stopFlag = AtomicFlag()
    private var thread: Thread?
    private let path = (NSTemporaryDirectory() as NSString).appendingPathComponent("stress_disk.tmp")

    init(log: ActivityLog) {
        self.log = log
    }

    func start() {
        guard !isRunning else { return }
        stopFlag.clear()
        let size = sizeMB
        let mode = self.mode
        isRunning = true
        statusText = "\(mode.rawValue) · \(size) MB"
        log.log("Disk: \(mode.rawValue), \(size) MB")

        let thread = Thread { [weak self] in self?.run(sizeMB: size, mode: mode) }
        thread.qualityOfService = .userInitiated
        self.thread = thread
        thread.start()
    }

    func stop() {
        guard isRunning else { return }
        stopFlag.set()
        thread = nil
        isRunning = false
        speedMBps = 0
        statusText = "Idle"
        log.log("Disk: stopped")
    }

    private func run(sizeMB: Int, mode: DiskMode) {
        let blockSize = 1024 * 1024
        let total = sizeMB * blockSize
        defer { unlink(path) }

        if mode.isWrite {
            writeLoop(total: total, blockSize: blockSize, random: mode.isRandom)
        } else {
            prepareFile(total: total, blockSize: blockSize)
            if !stopFlag.isSet {
                readLoop(total: total, blockSize: blockSize, random: mode.isRandom)
            }
        }
    }

    private func openNoCache(flags: Int32) -> Int32 {
        let fd = open(path, flags, 0o644)
        if fd >= 0 { _ = fcntl(fd, F_NOCACHE, 1) }
        return fd
    }

    private func prepareFile(total: Int, blockSize: Int) {
        DispatchQueue.main.async { self.statusText = "Preparing \(total / (1024 * 1024)) MB…" }
        let fd = openNoCache(flags: O_WRONLY | O_CREAT | O_TRUNC)
        guard fd >= 0 else { return }
        defer { close(fd) }
        let data = [UInt8](repeating: 0xA5, count: blockSize)
        var written = 0
        data.withUnsafeBytes { raw in
            while written < total && !stopFlag.isSet {
                let n = write(fd, raw.baseAddress, blockSize)
                if n <= 0 { break }
                written += n
            }
        }
        fsync(fd)
    }

    private func writeLoop(total: Int, blockSize: Int, random: Bool) {
        DispatchQueue.main.async {
            self.statusText = "\(random ? "Random" : "Sequential") write…"
        }
        let data = [UInt8](repeating: 0x5A, count: blockSize)
        while !stopFlag.isSet {
            let fd = openNoCache(flags: O_WRONLY | O_CREAT | O_TRUNC)
            guard fd >= 0 else { return }
            var written = 0
            let startTime = Date()
            data.withUnsafeBytes { raw in
                while written < total && !stopFlag.isSet {
                    if random {
                        let offset = off_t(Int.random(in: 0...max(0, total - blockSize)))
                        lseek(fd, offset, SEEK_SET)
                    }
                    let n = write(fd, raw.baseAddress, blockSize)
                    if n <= 0 { break }
                    written += n
                }
            }
            fsync(fd)
            close(fd)
            report(bytes: written, since: startTime)
        }
    }

    private func readLoop(total: Int, blockSize: Int, random: Bool) {
        DispatchQueue.main.async {
            self.statusText = "\(random ? "Random" : "Sequential") read…"
        }
        var buffer = [UInt8](repeating: 0, count: blockSize)
        while !stopFlag.isSet {
            let fd = openNoCache(flags: O_RDONLY)
            guard fd >= 0 else { return }
            var read = 0
            let startTime = Date()
            buffer.withUnsafeMutableBytes { raw in
                while read < total && !stopFlag.isSet {
                    if random {
                        let offset = off_t(Int.random(in: 0...max(0, total - blockSize)))
                        lseek(fd, offset, SEEK_SET)
                    }
                    let n = Darwin.read(fd, raw.baseAddress, blockSize)
                    if n <= 0 {
                        lseek(fd, 0, SEEK_SET)
                        if !random { break }
                        continue
                    }
                    read += n
                }
            }
            close(fd)
            report(bytes: read, since: startTime)
        }
    }

    private func report(bytes: Int, since start: Date) {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return }
        let mbps = (Double(bytes) / (1024 * 1024)) / elapsed
        DispatchQueue.main.async { self.speedMBps = mbps }
    }
}
