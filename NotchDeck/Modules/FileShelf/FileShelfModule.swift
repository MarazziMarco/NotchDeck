import SwiftUI

struct FileShelfModule: NotchModule {
    let id = "fileShelf"
    let displayName = "File Shelf"
    let iconName = "tray.full"
    let defaultEnabled = true
    let defaultHomeFavorite = true
    let defaultDashboardSize: ModuleDashboardSize = .small
    let defaultPriority = 20
    let defaultGroup: ModuleGroup = .home
    let category: ModuleCategory = .files

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView {
        switch size {
        case .large: return AnyView(FileShelfExpandedView())
        default: return AnyView(FileShelfCompactCard())
        }
    }
    func makeFocusView() -> AnyView { AnyView(FileShelfExpandedView()) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .wide]
    let defaultWidgetSize: DashboardWidgetSize = .small
    let preferredStyle: DashboardWidgetStyle = .tray
    let canLiveActivity = false
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(FileShelfWidget(size: size)) }
}
