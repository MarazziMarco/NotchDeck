import XCTest
@testable import NotchDeck

/// Deterministic metrics provider — never reads real battery/disk/uptime and
/// never launches a process or touches the network.
final class FakeSystemMetricsProvider: SystemMetricsProviding {
    var next: SystemPulseSnapshot
    private(set) var callCount = 0
    init(_ snapshot: SystemPulseSnapshot) { self.next = snapshot }
    func snapshot() -> SystemPulseSnapshot { callCount += 1; return next }
}

final class SystemPulseTests: XCTestCase {

    private let full = SystemPulseSnapshot(
        battery: BatteryMetric(percent: 82, charging: true),
        memoryUsedBytes: 9_000_000_000, memoryTotalBytes: 16_000_000_000,
        storageFreeBytes: 120_000_000_000, uptimeSeconds: 3 * 86_400 + 7 * 3600)

    // MARK: Provider / snapshot coherence

    func testFakeSnapshotIsCoherent() {
        let p = FakeSystemMetricsProvider(full)
        let s = p.snapshot()
        XCTAssertEqual(s.battery, BatteryMetric(percent: 82, charging: true))
        XCTAssertEqual(s.memoryTotalBytes, 16_000_000_000)
    }

    func testUnavailableBatteryHandledGracefully() {
        var snap = full; snap.battery = nil
        let vis = SystemPulseSettings.default.visibleMetrics(batteryAvailable: snap.battery != nil)
        XCTAssertFalse(vis.contains(.battery))
        XCTAssertFalse(vis.isEmpty, "other metrics still shown")
    }

    func testUnavailableStorageFormatsAsDash() {
        XCTAssertEqual(SystemPulseFormat.storageFree(nil), "—")
    }

    // MARK: Formatting

    func testPercentClamps() {
        XCTAssertEqual(SystemPulseFormat.percent(150), "100%")
        XCTAssertEqual(SystemPulseFormat.percent(-4), "0%")
        XCTAssertEqual(SystemPulseFormat.percent(63), "63%")
    }

    func testBatteryFormatShowsCharging() {
        XCTAssertEqual(SystemPulseFormat.battery(BatteryMetric(percent: 82, charging: true)), "82% ⚡")
        XCTAssertEqual(SystemPulseFormat.battery(BatteryMetric(percent: 50, charging: false)), "50%")
        XCTAssertEqual(SystemPulseFormat.battery(nil), "No battery")
    }

    func testUptimeFormat() {
        XCTAssertEqual(SystemPulseFormat.uptime(3 * 86_400 + 7 * 3600), "3d 7h")
        XCTAssertEqual(SystemPulseFormat.uptime(7 * 3600 + 12 * 60), "7h 12m")
        XCTAssertEqual(SystemPulseFormat.uptime(12 * 60), "12m")
        XCTAssertEqual(SystemPulseFormat.uptime(nil), "—")
    }

    func testByteFormatNonEmpty() {
        XCTAssertNotEqual(SystemPulseFormat.bytes(16_000_000_000), "—")
        XCTAssertEqual(SystemPulseFormat.bytes(nil), "—")
        XCTAssertEqual(SystemPulseFormat.bytes(-1), "—")
    }

    func testAccessibilityDescription() {
        XCTAssertEqual(SystemPulseFormat.accessibility(.battery, full), "Battery, 82 percent, charging")
        var snap = full; snap.battery = nil
        XCTAssertEqual(SystemPulseFormat.accessibility(.battery, snap), "Battery, unavailable")
    }

    // MARK: Lifecycle (no polling unless visible; no duplicate timers)

    @MainActor
    func testServiceDoesNotPollBeforeActivate() {
        let p = FakeSystemMetricsProvider(full)
        let svc = SystemPulseService(provider: p)
        XCTAssertFalse(svc.isPolling)
        XCTAssertEqual(p.callCount, 0)
    }

    @MainActor
    func testActivateRefreshesImmediatelyAndPolls() {
        let p = FakeSystemMetricsProvider(full)
        let svc = SystemPulseService(provider: p)
        svc.activate()
        XCTAssertTrue(svc.isPolling)
        XCTAssertEqual(p.callCount, 1, "refreshes immediately on appear")
        XCTAssertEqual(svc.snapshot.battery?.percent, 82)
    }

    @MainActor
    func testDeactivateStopsPolling() {
        let svc = SystemPulseService(provider: FakeSystemMetricsProvider(full))
        svc.activate()
        svc.deactivate()
        XCTAssertFalse(svc.isPolling)
    }

    @MainActor
    func testNoDuplicateTimerOnRepeatedActivate() {
        let svc = SystemPulseService(provider: FakeSystemMetricsProvider(full))
        svc.activate()
        svc.activate()
        XCTAssertTrue(svc.isPolling)
        svc.deactivate()
        XCTAssertFalse(svc.isPolling, "single timer torn down cleanly")
    }

    @MainActor
    func testIntervalChangeWhileActiveKeepsPolling() {
        let svc = SystemPulseService(provider: FakeSystemMetricsProvider(full))
        svc.activate()
        svc.interval = SystemPulseInterval.s60.seconds
        XCTAssertTrue(svc.isPolling)
    }

    // MARK: Settings invariants

    func testKeepsAtLeastOneMetric() {
        var s = SystemPulseSettings.default
        s.setShown(.memory, false); s.setShown(.storage, false); s.setShown(.uptime, false)
        s.setShown(.battery, false)   // would hide the last one
        XCTAssertTrue(s.showBattery, "last metric cannot be hidden")
        XCTAssertEqual(s.shownCount, 1)
    }

    func testHidingPrimaryReassignsPrimary() {
        var s = SystemPulseSettings.default
        s.primaryMetric = .battery
        s.setShown(.battery, false)
        XCTAssertNotEqual(s.primaryMetric, .battery)
        XCTAssertTrue(s.isShown(s.primaryMetric))
    }

    func testPrimaryBatteryFallsBackWhenNoBattery() {
        let s = SystemPulseSettings.default   // primary = battery
        let vis = s.visibleMetrics(batteryAvailable: false)
        XCTAssertEqual(vis.first, .memory, "battery primary falls back to memory when absent")
    }

    func testVisibleMetricsPrimaryFirst() {
        var s = SystemPulseSettings.default
        s.primaryMetric = .storage
        let vis = s.visibleMetrics(batteryAvailable: true)
        XCTAssertEqual(vis.first, .storage)
    }

    func testSettingsCodableRoundTrip() throws {
        var s = SystemPulseSettings.default
        s.primaryMetric = .uptime; s.refreshInterval = .s30; s.showBattery = false
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(SystemPulseSettings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testResetToDefault() {
        var s = SystemPulseSettings.default
        s.showBattery = false; s.refreshInterval = .s60
        s = .default
        XCTAssertTrue(s.showBattery)
        XCTAssertEqual(s.refreshInterval, .s15)
    }

    @MainActor
    func testEnvironmentRegistersSystemPulse() {
        let env = AppEnvironment(settings: SettingsStore.inMemory(), mediaProvider: FakeNowPlayingProvider())
        XCTAssertNotNil(env.community.descriptor(identifier: "community.system-pulse"))
        XCTAssertFalse(env.community.isEnabled("community.system-pulse"), "disabled by default")
    }
}
