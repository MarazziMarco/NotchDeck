import SwiftUI

struct MirrorModule: NotchModule {
    let id = "mirror"
    let displayName = "Mirror"
    let iconName = "web.camera"
    let defaultEnabled = true
    let defaultHomeFavorite = true
    let defaultDashboardSize: ModuleDashboardSize = .medium
    let requiredPermission: AppPermission? = .camera
    let defaultPriority = 30
    let defaultGroup: ModuleGroup = .home
    let category: ModuleCategory = .media

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView {
        switch size {
        case .large: return AnyView(MirrorExpandedView())
        default: return AnyView(MirrorCompactCard())
        }
    }
    func makeFocusView() -> AnyView { AnyView(MirrorExpandedView()) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.compact, .small, .medium]
    let defaultWidgetSize: DashboardWidgetSize = .small
    let preferredStyle: DashboardWidgetStyle = .circular
    let canLiveActivity = false
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(MirrorWidget(size: size)) }
}
