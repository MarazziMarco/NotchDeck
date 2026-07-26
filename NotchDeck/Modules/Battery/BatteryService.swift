import Foundation
import IOKit.ps
import Combine

/// A battery reading for a device.
struct BatteryDevice: Identifiable, Equatable {
    var id: String
    var name: String
    var percent: Int
    var charging: Bool
    var symbol: String
    var isCritical: Bool { percent <= 15 && !charging }
}

/// Reads the internal battery via IOKit power sources (public) plus a best-effort
/// scan of Bluetooth device batteries via `ioreg`. No private APIs.
@MainActor
final class BatteryService: ObservableObject {
    @Published private(set) var devices: [BatteryDevice] = []
    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        refresh()
        let t = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }
    func stop() { timer?.invalidate(); timer = nil }

    func refresh() {
        var result: [BatteryDevice] = []
        if let internalBattery = Self.internalBattery() { result.append(internalBattery) }
        result.append(contentsOf: Self.bluetoothBatteries())
        devices = result
    }

    var criticalDevice: BatteryDevice? { devices.first { $0.isCritical } }

    // MARK: Internal battery (IOKit)

    nonisolated static func internalBattery() -> BatteryDevice? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any]
            else { continue }
            guard let cap = desc[kIOPSCurrentCapacityKey] as? Int,
                  let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            let percent = Int((Double(cap) / Double(max) * 100).rounded())
            let state = desc[kIOPSPowerSourceStateKey] as? String
            let charging = state == kIOPSACPowerValue
            return BatteryDevice(id: "internal", name: "This Mac", percent: percent,
                                 charging: charging, symbol: "laptopcomputer")
        }
        return nil
    }

    // MARK: Bluetooth devices (best-effort via ioreg)

    nonisolated static func bluetoothBatteries() -> [BatteryDevice] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-r", "-l", "-k", "BatteryPercent"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        do {
            try process.run(); process.waitUntilExit()
        } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var results: [BatteryDevice] = []
        var currentName: String?
        for line in text.split(separator: "\n") {
            if let r = line.range(of: "\"Product\" = \"") {
                currentName = String(line[r.upperBound...]).replacingOccurrences(of: "\"", with: "")
            }
            if let r = line.range(of: "\"BatteryPercent\" = ") {
                let value = line[r.upperBound...].trimmingCharacters(in: .whitespaces)
                if let percent = Int(value), percent > 0 {
                    let name = currentName ?? "Device"
                    let symbol = name.lowercased().contains("mouse") ? "magicmouse"
                        : (name.lowercased().contains("key") ? "keyboard"
                        : (name.lowercased().contains("trackpad") ? "trackpad" : "dot.radiowaves.right"))
                    results.append(BatteryDevice(id: name, name: name, percent: percent,
                                                 charging: false, symbol: symbol))
                    currentName = nil
                }
            }
        }
        return results
    }
}
