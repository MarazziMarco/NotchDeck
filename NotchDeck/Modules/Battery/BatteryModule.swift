import SwiftUI

struct BatteryModule: NotchModule {
    let id = "battery"
    let displayName = "Batteries"
    let iconName = "battery.100"
    let defaultEnabled = true
    let defaultHomeFavorite = false
    let defaultDashboardSize: ModuleDashboardSize = .small
    let defaultPriority = 80
    let category: ModuleCategory = .files
    let defaultGroup: ModuleGroup = .more
    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .wide]
    let defaultWidgetSize: DashboardWidgetSize = .medium
    let preferredStyle: DashboardWidgetStyle = .capsule

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView { AnyView(BatteryWidget(size: .medium)) }
    func makeFocusView() -> AnyView { AnyView(BatteryWidget(size: .wide)) }
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(BatteryWidget(size: size)) }
}

struct BatteryWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: BatteryService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack { Image(systemName: "battery.100").font(.system(size: 10))
                Text("Batteries").font(.system(size: 11, weight: .semibold)); Spacer() }
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            if service.devices.isEmpty {
                Text("No batteries").font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            } else {
                ForEach(service.devices.prefix(size == .small ? 1 : (size == .medium ? 2 : 4))) { d in
                    row(d)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { service.start() }
    }

    private func row(_ d: BatteryDevice) -> some View {
        HStack(spacing: 6) {
            Image(systemName: d.symbol).font(.system(size: 10)).frame(width: 16)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            // Capsule battery gauge.
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.08)).frame(height: 8)
                Capsule().fill(tint(d)).frame(width: max(4, CGFloat(d.percent) / 100 * 44), height: 8)
            }
            .frame(width: 44)
            Text("\(d.percent)%").font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(d.isCritical ? DesignTokens.Palette.statusFailure : DesignTokens.Palette.primaryText)
            if d.charging { Image(systemName: "bolt.fill").font(.system(size: 8)).foregroundStyle(DesignTokens.Palette.statusSuccess) }
            Spacer(minLength: 0)
        }
    }
    private func tint(_ d: BatteryDevice) -> Color {
        d.isCritical ? DesignTokens.Palette.statusFailure
            : (d.percent <= 30 ? DesignTokens.Palette.statusAttention : DesignTokens.Palette.statusSuccess)
    }
}
