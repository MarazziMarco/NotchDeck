import SwiftUI

struct ClipboardModule: NotchModule {
    let id = "clipboard"
    let displayName = "Clipboard"
    let iconName = "doc.on.clipboard"
    let defaultEnabled = true
    let defaultHomeFavorite = true
    let defaultDashboardSize: ModuleDashboardSize = .large
    let defaultPriority = 10
    let defaultGroup: ModuleGroup = .files
    let category: ModuleCategory = .files

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView {
        AnyView(ClipboardDashboardCard(size: size))
    }
    func makeFocusView() -> AnyView { AnyView(ClipboardExpandedView()) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .wide, .large]
    let defaultWidgetSize: DashboardWidgetSize = .wide
    let preferredStyle: DashboardWidgetStyle = .sheet
    let canLiveActivity = true
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(ClipboardWidget(size: size)) }
}

/// Size-aware Home card. Small/medium show a summary; large shows the list.
struct ClipboardDashboardCard: View {
    let size: ModuleDashboardSize
    @EnvironmentObject private var service: ClipboardService

    var body: some View {
        if size == .large {
            ClipboardExpandedView()
        } else {
            ModuleSummaryCard(
                icon: "doc.on.clipboard",
                title: "Clipboard",
                value: "\(service.history.items.count)",
                subtitle: service.history.items.first?.preview ?? "Nothing copied",
                tint: .neutral,
                compact: size == .small)
        }
    }
}
