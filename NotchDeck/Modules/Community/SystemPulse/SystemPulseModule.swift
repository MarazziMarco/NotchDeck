import SwiftUI

/// A real source-integrated **community** module (least-privilege: no sensitive
/// capabilities). Shows local Mac status — battery, memory, storage, uptime —
/// read locally via public APIs and never transmitted.
struct SystemPulseModule: NotchDeckModule {
    static let descriptor = ModuleDescriptor(
        identifier: "community.system-pulse",
        displayName: "System Pulse",
        summary: "Battery, memory, storage and uptime at a glance.",
        version: "1.0.0",
        author: "NotchDeck Contributors",
        category: .system,
        iconSystemName: "waveform.path.ecg",
        defaultEnabled: false,                       // community modules ship disabled
        surfaces: [.homeCard, .settingsSection],
        capabilities: [],                            // least privilege
        hasSettings: true)

    init() {}

    func homeCard(context: ModuleContext) -> AnyView? { AnyView(SystemPulseCard()) }
    func settingsView(context: ModuleContext) -> AnyView? { AnyView(SystemPulseSettingsView()) }
}

/// Polished Home card. Renders the enabled metrics from one coherent snapshot,
/// adapting the count to available height. Lifecycle-aware: the service polls
/// only while this card is on screen.
struct SystemPulseCard: View {
    @EnvironmentObject private var settings: SettingsStore
    @StateObject private var service = SystemPulseService()

    private var cfg: SystemPulseSettings { settings.settings.systemPulse }
    private var metrics: [SystemPulseMetric] {
        cfg.visibleMetrics(batteryAvailable: service.snapshot.battery != nil)
    }

    var body: some View {
        GeometryReader { geo in
            // Small → 2 metrics; medium → up to 4; large → all enabled.
            let maxRows = geo.size.height < 90 ? 2 : (geo.size.height < 150 ? 3 : 4)
            VStack(alignment: .leading, spacing: 4) {
                Label("System Pulse", systemImage: "waveform.path.ecg")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                ForEach(Array(metrics.prefix(maxRows)), id: \.self) { row($0) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(10)
        }
        .onAppear {
            service.interval = cfg.refreshInterval.seconds
            service.activate()
        }
        .onDisappear { service.deactivate() }
        .onChange(of: cfg.refreshInterval) { _, v in service.interval = v.seconds }
    }

    @ViewBuilder private func row(_ m: SystemPulseMetric) -> some View {
        HStack(spacing: 6) {
            Image(systemName: m.symbol).font(.system(size: 10))
                .foregroundStyle(DesignTokens.Palette.tertiaryText).frame(width: 16)
            Text(m.label).font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer(minLength: 6)
            Text(value(m)).font(.system(size: 11, weight: .medium)).monospacedDigit()
                .foregroundStyle(DesignTokens.Palette.primaryText).lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SystemPulseFormat.accessibility(m, service.snapshot)))
    }

    private func value(_ m: SystemPulseMetric) -> String {
        let s = service.snapshot
        switch m {
        case .battery: return SystemPulseFormat.battery(s.battery)
        case .memory: return SystemPulseFormat.memory(used: s.memoryUsedBytes, total: s.memoryTotalBytes)
        case .storage: return SystemPulseFormat.storageFree(s.storageFreeBytes)
        case .uptime: return SystemPulseFormat.uptime(s.uptimeSeconds)
        }
    }
}

/// Module-specific settings shown in the Modules detail screen.
struct SystemPulseSettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    private var cfg: Binding<SystemPulseSettings> { $settings.settings.systemPulse }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Metrics").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            ForEach(SystemPulseMetric.allCases) { m in
                Toggle(m.label, isOn: Binding(
                    get: { settings.settings.systemPulse.isShown(m) },
                    set: { settings.settings.systemPulse.setShown(m, $0) }))
            }
            Divider()
            Picker("Primary metric", selection: cfg.primaryMetric) {
                ForEach(SystemPulseMetric.allCases.filter { settings.settings.systemPulse.isShown($0) }) {
                    Text($0.label).tag($0)
                }
            }
            Picker("Refresh interval", selection: cfg.refreshInterval) {
                ForEach(SystemPulseInterval.allCases) { Text($0.label).tag($0) }
            }
            Text("No additional permissions required. System information is read locally and is not transmitted.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
