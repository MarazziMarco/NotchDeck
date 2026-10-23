import SwiftUI
import SharedWidgets

/// The same shared timetable can also be placed on NotchDeck's widget dashboard.
struct TimetableDashboardModule: NotchModule {
    let id = "sharedTimetable"
    let displayName = "Shared Timetable"
    let iconName = "calendar.badge.clock"
    let defaultEnabled = true
    let defaultHomeFavorite = false
    let defaultPriority = 65
    let defaultGroup: ModuleGroup = .more
    let supportedSizes: [ModuleDashboardSize] = [.medium, .large]
    let defaultDashboardSize: ModuleDashboardSize = .large
    let supportedWidgetSizes: [DashboardWidgetSize] = [.wide, .large]
    let defaultWidgetSize: DashboardWidgetSize = .large
    let preferredStyle: DashboardWidgetStyle = .custom
    let canLiveActivity = false
    @MainActor func makeDashboardCard(size: ModuleDashboardSize) -> AnyView {
        AnyView(SharedTimetableView(channel: SharedWidgetLibrary.shared.timetable, presentation: size == .large ? .overview : .week))
    }
    @MainActor func makeFocusView() -> AnyView {
        AnyView(SharedTimetableView(channel: SharedWidgetLibrary.shared.timetable, presentation: .overview))
    }
    @MainActor func makeWidget(size: DashboardWidgetSize) -> AnyView {
        AnyView(SharedTimetableView(channel: SharedWidgetLibrary.shared.timetable, presentation: size == .large ? .overview : .week))
    }
}
