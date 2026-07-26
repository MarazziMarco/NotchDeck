import SwiftUI

struct DownloadsModule: NotchModule {
    let id = "downloads"
    let displayName = "Downloads"
    let iconName = "arrow.down.circle"
    let defaultEnabled = true
    let defaultHomeFavorite = false
    let defaultDashboardSize: ModuleDashboardSize = .medium
    let defaultPriority = 70
    let category: ModuleCategory = .files
    let defaultGroup: ModuleGroup = .files
    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .wide]
    let defaultWidgetSize: DashboardWidgetSize = .medium
    let preferredStyle: DashboardWidgetStyle = .tile

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView { AnyView(DownloadsWidget(size: .medium)) }
    func makeFocusView() -> AnyView { AnyView(DownloadsWidget(size: .wide)) }
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(DownloadsWidget(size: size)) }
}

struct DownloadsWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: DownloadsService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "arrow.down.circle").font(.system(size: 10))
                Text("Downloads").font(.system(size: 11, weight: .semibold))
                Spacer()
                if service.activeCount > 0 {
                    HStack(spacing: 3) {
                        Circle().fill(DesignTokens.Palette.statusRunning).frame(width: 5, height: 5)
                        Text("\(service.activeCount)").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(DesignTokens.Palette.statusRunning)
                }
            }
            .foregroundStyle(DesignTokens.Palette.secondaryText)
            content
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture { service.openFolder() }
        .task { service.start() }
    }

    @ViewBuilder private var content: some View {
        if service.items.isEmpty {
            Text("No recent downloads").font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
        } else if size == .small {
            if let first = service.items.first {
                Text(first.name).font(.system(size: 10)).lineLimit(1)
                    .foregroundStyle(DesignTokens.Palette.primaryText)
            }
        } else {
            ForEach(service.items.prefix(size == .medium ? 3 : 5)) { item in
                HStack(spacing: 5) {
                    Image(systemName: item.isActive ? "arrow.down.circle.fill" : "doc")
                        .font(.system(size: 9))
                        .foregroundStyle(item.isActive ? DesignTokens.Palette.statusRunning : DesignTokens.Palette.tertiaryText)
                    Text(item.name).font(.system(size: 10)).lineLimit(1)
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}
