import Foundation

enum SystemPulseInterval: Int, Codable, CaseIterable, Identifiable {
    case s5 = 5, s15 = 15, s30 = 30, s60 = 60
    var id: Int { rawValue }
    var seconds: TimeInterval { TimeInterval(rawValue) }
    var label: String { "\(rawValue) seconds" }
}

/// Persisted System Pulse configuration. Stored inside `AppSettings` (one JSON
/// blob) — no scattered global UserDefaults keys.
struct SystemPulseSettings: Codable, Equatable {
    var showBattery = true
    var showMemory = true
    var showStorage = true
    var showUptime = true
    var refreshInterval: SystemPulseInterval = .s15
    var primaryMetric: SystemPulseMetric = .battery

    /// Enabled metrics in a stable priority order (primary first).
    func visibleMetrics(batteryAvailable: Bool) -> [SystemPulseMetric] {
        var order: [SystemPulseMetric] = [primaryMetric] + SystemPulseMetric.allCases.filter { $0 != primaryMetric }
        // If the primary is battery but there is none, fall back to the next.
        if primaryMetric == .battery && !batteryAvailable {
            order = SystemPulseMetric.allCases.filter { $0 != .battery } + [.battery]
        }
        return order.filter { isShown($0) && !($0 == .battery && !batteryAvailable) }
    }

    func isShown(_ m: SystemPulseMetric) -> Bool {
        switch m {
        case .battery: return showBattery
        case .memory: return showMemory
        case .storage: return showStorage
        case .uptime: return showUptime
        }
    }

    var shownCount: Int { [showBattery, showMemory, showStorage, showUptime].filter { $0 }.count }

    /// Toggle a metric, but never allow every metric to be hidden.
    mutating func setShown(_ m: SystemPulseMetric, _ shown: Bool) {
        if !shown && shownCount <= 1 && isShown(m) { return }   // keep at least one
        switch m {
        case .battery: showBattery = shown
        case .memory: showMemory = shown
        case .storage: showStorage = shown
        case .uptime: showUptime = shown
        }
        // Keep the primary valid.
        if !isShown(primaryMetric), let first = SystemPulseMetric.allCases.first(where: isShown) {
            primaryMetric = first
        }
    }

    static let `default` = SystemPulseSettings()
}
