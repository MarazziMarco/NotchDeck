import SwiftUI
import SharedWidgets

protocol SharedCardModule: NotchModule { var widgetKind: ProductivityWidgetKind { get } }
extension SharedCardModule {
    var displayName: String { widgetKind.title }
    var iconName: String { widgetKind.symbol }
    var defaultEnabled: Bool { true }
    var defaultHomeFavorite: Bool { false }
    var defaultDashboardSize: ModuleDashboardSize { .medium }
    var supportedSizes: [ModuleDashboardSize] { [.small, .medium, .large] }
    var defaultGroup: ModuleGroup { .more }
    var supportedWidgetSizes: [DashboardWidgetSize] { [.small, .medium, .wide, .large] }
    var defaultWidgetSize: DashboardWidgetSize { .medium }
    var preferredStyle: DashboardWidgetStyle { .custom }
    var canLiveActivity: Bool { false }
    @MainActor func makeDashboardCard(size: ModuleDashboardSize) -> AnyView { AnyView(SharedProductivityWidget(kind: widgetKind)) }
    @MainActor func makeFocusView() -> AnyView { AnyView(SharedProductivityWidget(kind: widgetKind)) }
    @MainActor func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(SharedProductivityWidget(kind: widgetKind)) }
}
struct SharedCountdownModule: SharedCardModule {
    let id = "sharedCountdown"
    let widgetKind = ProductivityWidgetKind.countdown
    let defaultPriority = 70
}
struct SharedHabitsModule: SharedCardModule {
    let id = "sharedHabits"
    let widgetKind = ProductivityWidgetKind.habits
    let defaultPriority = 71
}

struct SharedRoutineModule: NotchModule {
    let id = "sharedRoutine"
    let displayName = "Routine · Palestra"
    let iconName = "dumbbell"
    let defaultEnabled = true
    let defaultHomeFavorite = false
    let defaultDashboardSize: ModuleDashboardSize = .large
    let supportedSizes: [ModuleDashboardSize] = [.medium, .large]
    let defaultGroup: ModuleGroup = .more
    let defaultPriority = 72
    let supportedWidgetSizes: [DashboardWidgetSize] = [.wide, .large]
    let defaultWidgetSize: DashboardWidgetSize = .large
    let preferredStyle: DashboardWidgetStyle = .custom
    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView { AnyView(SharedRoutineWidget()) }
    func makeFocusView() -> AnyView { AnyView(SharedRoutineWidget()) }
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(SharedRoutineWidget()) }
}
