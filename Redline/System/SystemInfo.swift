import Foundation

/// Static facts about the machine, read once at launch via `sysctl`.
struct SystemInfo {
    let cpuBrand: String
    let logicalCores: Int
    let physicalCores: Int
    let pCores: Int?
    let eCores: Int?
    let totalRAM: UInt64
    let model: String
    let osVersion: String

    /// A trimmed CPU name suitable for a compact chip (drops Intel boilerplate).
    var shortCPU: String {
        var s = cpuBrand
            .replacingOccurrences(of: "(R)", with: "")
            .replacingOccurrences(of: "(TM)", with: "")
            .replacingOccurrences(of: "CPU", with: "")
        if let at = s.range(of: " @") { s = String(s[..<at.lowerBound]) }
        let collapsed = s.split(whereSeparator: { $0 == " " }).joined(separator: " ")
        return collapsed.isEmpty ? "Processor" : collapsed
    }

    var coresLabel: String {
        if let p = pCores, let e = eCores {
            return "\(logicalCores) Cores · \(p)P + \(e)E"
        }
        return "\(logicalCores) Cores"
    }

    var ramLabel: String {
        "\(Int((Double(totalRAM) / 1_073_741_824).rounded())) GB RAM"
    }

    static func current() -> SystemInfo {
        let brand = sysctlString("machdep.cpu.brand_string") ?? "Unknown CPU"
        let logical = sysctlInt("hw.logicalcpu") ?? ProcessInfo.processInfo.activeProcessorCount
        let physical = sysctlInt("hw.physicalcpu") ?? logical
        let p = sysctlInt("hw.perflevel0.logicalcpu")
        let e = sysctlInt("hw.perflevel1.logicalcpu")
        let mem = sysctlInt("hw.memsize").map { UInt64($0) } ?? ProcessInfo.processInfo.physicalMemory
        let model = sysctlString("hw.model") ?? "Mac"
        let v = ProcessInfo.processInfo.operatingSystemVersion
        let os = v.patchVersion > 0
            ? "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
            : "\(v.majorVersion).\(v.minorVersion)"
        return SystemInfo(cpuBrand: brand, logicalCores: logical, physicalCores: physical,
                          pCores: p, eCores: e, totalRAM: mem, model: model, osVersion: os)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var value = 0
        var size = MemoryLayout<Int>.size
        guard sysctlbyname(name, &value, &size, nil, 0) == 0 else { return nil }
        return value
    }
}
