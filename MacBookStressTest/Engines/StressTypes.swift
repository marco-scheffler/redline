import Foundation

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
final class AtomicFlag {
    private var value = false
    private let lock = NSLock()

    func set() { lock.lock(); value = true; lock.unlock() }
    func clear() { lock.lock(); value = false; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
}

// MARK: - Activity log

/// Append-only, timestamped activity feed shown at the bottom of the window.
final class ActivityLog: ObservableObject {
    struct Entry: Identifiable {
        let id = UUID()
        let time: String
        let message: String
    }

    @Published private(set) var entries: [Entry] = []

    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    func log(_ message: String) {
        let stamp = formatter.string(from: Date())
        DispatchQueue.main.async {
            self.entries.append(Entry(time: stamp, message: message))
            if self.entries.count > 200 {
                self.entries.removeFirst(self.entries.count - 200)
            }
        }
    }
}
