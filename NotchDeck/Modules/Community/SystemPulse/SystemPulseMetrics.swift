import Foundation
import IOKit.ps
import Darwin

/// A single battery reading. `percent` is clamped to 0…100 by the provider.
struct BatteryMetric: Equatable {
    var percent: Int
    var charging: Bool
}

/// One coherent snapshot of local system metrics, captured together so the UI
/// never mixes readings from different moments. Any field is nil when that metric
/// is unavailable (e.g. no battery on a desktop Mac).
struct SystemPulseSnapshot: Equatable {
    var battery: BatteryMetric?
    var memoryUsedBytes: Int64?
    var memoryTotalBytes: Int64?
    var storageFreeBytes: Int64?
    var uptimeSeconds: TimeInterval?

    static let empty = SystemPulseSnapshot()
}

/// Which metrics System Pulse can show (also the "primary metric" choices).
enum SystemPulseMetric: String, Codable, CaseIterable, Identifiable {
    case battery, memory, storage, uptime
    var id: String { rawValue }
    var label: String {
        switch self { case .battery: return "Battery"; case .memory: return "Memory"
                      case .storage: return "Storage"; case .uptime: return "Uptime" }
    }
    var symbol: String {
        switch self { case .battery: return "battery.100"; case .memory: return "memorychip"
                      case .storage: return "internaldrive"; case .uptime: return "clock.arrow.circlepath" }
    }
}

/// The metrics boundary — injected so tests never read the real battery,
/// filesystem capacity or uptime.
protocol SystemMetricsProviding: AnyObject {
    /// One coherent snapshot. Must not launch processes or touch the network.
    func snapshot() -> SystemPulseSnapshot
}

/// Locale-aware, safe formatting for the metrics (pure + testable).
enum SystemPulseFormat {
    static func percent(_ p: Int) -> String { "\(min(100, max(0, p)))%" }

    static func bytes(_ value: Int64?) -> String {
        guard let value, value >= 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useGB, .useMB]
        return f.string(fromByteCount: value)
    }

    /// "9.2 / 16 GB" style used/total.
    static func memory(used: Int64?, total: Int64?) -> String {
        guard let used, let total, total > 0, used >= 0 else { return "—" }
        let f = ByteCountFormatter(); f.countStyle = .file; f.allowedUnits = [.useGB]
        return "\(bytes(used)) / \(f.string(fromByteCount: total))"
    }

    static func storageFree(_ free: Int64?) -> String {
        guard let free, free >= 0 else { return "—" }
        return "\(bytes(free)) free"
    }

    /// Compact uptime: "3d 7h", "7h 12m", "12m".
    static func uptime(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds >= 0 else { return "—" }
        let s = Int(seconds)
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    static func battery(_ b: BatteryMetric?) -> String {
        guard let b else { return "No battery" }
        return percent(b.percent) + (b.charging ? " ⚡" : "")
    }

    /// Full VoiceOver description for a metric value.
    static func accessibility(_ metric: SystemPulseMetric, _ snap: SystemPulseSnapshot) -> String {
        switch metric {
        case .battery:
            guard let b = snap.battery else { return "Battery, unavailable" }
            return "Battery, \(min(100, max(0, b.percent))) percent, \(b.charging ? "charging" : "not charging")"
        case .memory:
            return "Memory, " + memory(used: snap.memoryUsedBytes, total: snap.memoryTotalBytes)
        case .storage:
            return "Storage, " + storageFree(snap.storageFreeBytes)
        case .uptime:
            return "Uptime, " + uptime(snap.uptimeSeconds)
        }
    }
}

/// Production provider — public macOS APIs only. No processes, no osascript, no
/// private frameworks, no network.
final class SystemMetricsProvider: SystemMetricsProviding {
    func snapshot() -> SystemPulseSnapshot {
        SystemPulseSnapshot(
            battery: readBattery(),
            memoryUsedBytes: readMemoryUsed(),
            memoryTotalBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            storageFreeBytes: readStorageFree(),
            uptimeSeconds: ProcessInfo.processInfo.systemUptime)
    }

    private func readBattery() -> BatteryMetric? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let first = sources.first,
              let desc = IOPSGetPowerSourceDescription(blob, first)?.takeUnretainedValue() as? [String: Any]
        else { return nil }
        guard let cur = desc[kIOPSCurrentCapacityKey] as? Int,
              let maxCap = desc[kIOPSMaxCapacityKey] as? Int, maxCap > 0 else { return nil }
        let pct = min(100, max(0, Int((Double(cur) / Double(maxCap) * 100).rounded())))
        let state = desc[kIOPSPowerSourceStateKey] as? String
        let charging = (desc[kIOPSIsChargingKey] as? Bool) ?? (state == kIOPSACPowerValue)
        return BatteryMetric(percent: pct, charging: charging)
    }

    private func readMemoryUsed() -> Int64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let page = Int64(vm_kernel_page_size)
        // "Used" ≈ active + wired + compressed (excludes free/inactive).
        let used = (Int64(stats.active_count) + Int64(stats.wire_count) + Int64(stats.compressor_page_count)) * page
        return used >= 0 ? used : nil
    }

    private func readStorageFree() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let v = values?.volumeAvailableCapacityForImportantUsage { return v }
        let fallback = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return fallback?.volumeAvailableCapacity.map(Int64.init)
    }
}
