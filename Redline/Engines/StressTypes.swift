import Foundation
import os

// MARK: - Configuration enums

enum CPUWorkload: String, CaseIterable, Identifiable {
    case float = "Float"
    case integer = "Integer"
    case mixed = "Mixed"
    var id: String { rawValue }
}

enum CPUDuration: String, CaseIterable, Identifiable {
    case s30 = "30s"
    case m1 = "1m"
    case m5 = "5m"
    case m30 = "30m"
    case unlimited = "∞"
    var id: String { rawValue }

    var seconds: Int? {
        switch self {
        case .s30: return 30
        case .m1: return 60
        case .m5: return 300
        case .m30: return 1800
        case .unlimited: return nil
        }
    }
}

enum DiskMode: String, CaseIterable, Identifiable {
    case seqWrite = "Seq W"
    case seqRead = "Seq R"
    case randWrite = "Rnd W"
    case randRead = "Rnd R"
    var id: String { rawValue }

    var isWrite: Bool { self == .seqWrite || self == .randWrite }
    var isRandom: Bool { self == .randWrite || self == .randRead }
}

// MARK: - Thread-safe stop flag

/// A tiny lock-protected boolean used to ask worker threads to stop cooperatively.
/// Workers poll `isSet` only once per outer batch, so lock overhead is negligible.
/// Each run gets a fresh flag, so a worker that is slow to notice a stop can never
/// be revived by the next start.
final class AtomicFlag: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: false)

    func set() { value.withLock { $0 = true } }
    var isSet: Bool { value.withLock { $0 } }

    /// Runs `update` on the main actor unless this run has been stopped by then,
    /// so a finishing worker can't overwrite the state of a newer run.
    func onMainUnlessSet(_ update: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async { if !self.isSet { update() } }
    }
}

// MARK: - Activity log

/// Append-only, timestamped activity feed shown at the bottom of the window.
@MainActor @Observable
final class ActivityLog {
    struct Entry: Identifiable {
        let id = UUID()
        let time: String
        let message: String
    }

    private(set) var entries: [Entry] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    /// Callable from any thread; the entry is appended on the main actor.
    nonisolated func log(_ message: String) {
        let now = Date()
        DispatchQueue.main.async {
            self.entries.append(Entry(time: self.formatter.string(from: now), message: message))
            if self.entries.count > 200 {
                self.entries.removeFirst(self.entries.count - 200)
            }
        }
    }
}
