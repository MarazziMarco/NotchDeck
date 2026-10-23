import SwiftUI
import SharedWidgets

struct PomodoroModule: NotchModule {
    let id = "pomodoro"
    let displayName = "Pomodoro"
    let iconName = "timer"
    let defaultEnabled = true          // available but off by default
    let defaultHomeFavorite = true
    let defaultDashboardSize: ModuleDashboardSize = .small
    let requiredPermission: AppPermission? = .notifications
    let defaultPriority = 40
    let defaultGroup: ModuleGroup = .focus

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView { AnyView(SharedProductivityWidget(kind: .focus)) }
    func makeFocusView() -> AnyView { AnyView(SharedProductivityWidget(kind: .focus)) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.compact, .small, .wide]
    let defaultWidgetSize: DashboardWidgetSize = .small
    let preferredStyle: DashboardWidgetStyle = .custom
    let canLiveActivity = true
    func makeWidget(size: DashboardWidgetSize) -> AnyView {
        if size == .compact { return AnyView(PomodoroWidget(size: size)) }
        return AnyView(SharedProductivityWidget(kind: .focus))
    }
}
