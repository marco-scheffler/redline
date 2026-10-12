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
    private var stopFlag: AtomicFlag?
    private var thread: Thread?
    private let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

    init(log: ActivityLog) {
        self.log = log
    }

    func start() {
        guard !isRunning else { return }
        let size = sizeMB
        let mode = self.mode

        // Keep 1 GB headroom so the test never fills the disk.
        let free = (try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?
            .volumeAvailableCapacity
        if let free, free < (size + 1024) * 1024 * 1024 {
            log.log("Disk: not enough free space for \(size) MB (\(free / (1024 * 1024)) MB free)")
            return
        }

        let stopFlag = AtomicFlag()
        self.stopFlag = stopFlag
        isRunning = true
        statusText = "\(mode.rawValue) · \(size) MB"
        log.log("Disk: \(mode.rawValue), \(size) MB")

        let thread = Thread { [weak self] in self?.run(sizeMB: size, mode: mode, stop: stopFlag) }
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
        speedMBps = 0
        statusText = "Idle"
        log.log("Disk: stopped")
    }

    private func run(sizeMB: Int, mode: DiskMode, stop: AtomicFlag) {
        let blockSize = 1024 * 1024
        let total = sizeMB * blockSize

        guard let fd = makeTempFile() else {
            fail("Disk: cannot create temp file", stop: stop)
            return
        }
        defer { close(fd) }

        if mode.isWrite {
            writeLoop(fd: fd, total: total, blockSize: blockSize, random: mode.isRandom, stop: stop)
        } else if prepareFile(fd: fd, total: total, blockSize: blockSize, stop: stop) {
            readLoop(fd: fd, total: total, blockSize: blockSize, random: mode.isRandom, stop: stop)
        }
    }

    /// Creates a uniquely named file and unlinks it right away: it lives only as long as
    /// the descriptor, so concurrent runs can't collide and a crash leaves nothing behind.
    private func makeTempFile() -> Int32? {
        var template = Array(directory.appendingPathComponent("redline_disk.XXXXXX").path.utf8CString)
        let fd = mkstemp(&template)
        guard fd >= 0 else { return nil }
        unlink(template)
        _ = fcntl(fd, F_NOCACHE, 1)
        return fd
    }

    private func prepareFile(fd: Int32, total: Int, blockSize: Int, stop: AtomicFlag) -> Bool {
        stop.onMainUnlessSet { self.statusText = "Preparing \(total / (1024 * 1024)) MB…" }
        let data = [UInt8](repeating: 0xA5, count: blockSize)
        var written = 0
        let ok = data.withUnsafeBytes { raw -> Bool in
            while written < total && !stop.isSet {
                let n = write(fd, raw.baseAddress, blockSize)
                if n < 0 { return false }
                written += n
            }
            return true
        }
        guard ok else {
            fail("Disk: write failed (\(String(cString: strerror(errno))))", stop: stop)
            return false
        }
        fsync(fd)
        return !stop.isSet
    }

    private func writeLoop(fd: Int32, total: Int, blockSize: Int, random: Bool, stop: AtomicFlag) {
        stop.onMainUnlessSet {
            self.statusText = "\(random ? "Random" : "Sequential") write…"
        }
        let data = [UInt8](repeating: 0x5A, count: blockSize)
        while !stop.isSet {
            lseek(fd, 0, SEEK_SET)
            var written = 0
            let startTime = Date()
            let ok = data.withUnsafeBytes { raw -> Bool in
                while written < total && !stop.isSet {
                    if random {
                        let offset = off_t(Int.random(in: 0...max(0, total - blockSize)))
                        lseek(fd, offset, SEEK_SET)
                    }
                    let n = write(fd, raw.baseAddress, blockSize)
                    if n < 0 { return false }
                    written += n
                }
                return true
            }
            guard ok else {
                fail("Disk: write failed (\(String(cString: strerror(errno))))", stop: stop)
                return
            }
            fsync(fd)
            report(bytes: written, since: startTime, stop: stop)
        }
    }

    private func readLoop(fd: Int32, total: Int, blockSize: Int, random: Bool, stop: AtomicFlag) {
        stop.onMainUnlessSet {
            self.statusText = "\(random ? "Random" : "Sequential") read…"
        }
        var buffer = [UInt8](repeating: 0, count: blockSize)
        while !stop.isSet {
            lseek(fd, 0, SEEK_SET)
            var read = 0
            let startTime = Date()
            let ok = buffer.withUnsafeMutableBytes { raw -> Bool in
                while read < total && !stop.isSet {
                    if random {
                        let offset = off_t(Int.random(in: 0...max(0, total - blockSize)))
                        lseek(fd, offset, SEEK_SET)
                    }
                    let n = Darwin.read(fd, raw.baseAddress, blockSize)
                    if n < 0 { return false }
                    if n == 0 {
                        lseek(fd, 0, SEEK_SET)
                        if !random { break }
                        continue
                    }
                    read += n
                }
                return true
            }
            guard ok else {
                fail("Disk: read failed (\(String(cString: strerror(errno))))", stop: stop)
                return
            }
            report(bytes: read, since: startTime, stop: stop)
        }
    }

    private func report(bytes: Int, since start: Date, stop: AtomicFlag) {
        let elapsed = Date().timeIntervalSince(start)
        guard elapsed > 0 else { return }
        let mbps = (Double(bytes) / (1024 * 1024)) / elapsed
        stop.onMainUnlessSet { self.speedMBps = mbps }
    }

    /// Logs a failure and returns the card to idle, unless the run was already stopped.
    private func fail(_ message: String, stop: AtomicFlag) {
        log.log(message)
        stop.onMainUnlessSet {
            self.isRunning = false
            self.speedMBps = 0
            self.statusText = "Idle"
        }
    }
}
