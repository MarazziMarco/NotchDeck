import SwiftUI

/// Grouped Utilities tabs (iteration 9). Home = curated dashboard; Focus =
/// Pomodoro; Files = clipboard/downloads/screen/batteries; More = library.
enum UtilitiesTab: String, CaseIterable, Identifiable {
    case home, focus, files, more
    var id: String { rawValue }
    var title: String { self == .more ? "More" : rawValue.capitalized }
    var fullTitle: String { title }
    var icon: String {
        switch self {
        case .home: return "house"
        case .focus: return "target"
        case .files: return "folder"
        case .more: return "square.grid.2x2"
        }
    }
    var group: ModuleGroup {
        switch self {
        case .home: return .home
        case .focus: return .focus
        case .files: return .files
        case .more: return .more
        }
    }
    var widthProfile: UtilitiesWidthProfile {
        switch self {
        case .home: return .home
        case .focus: return .focus
        case .files: return .files
        case .more: return .more
        }
    }
}

/// Utilities face: a responsive tab bar over category dashboards.
struct UtilitiesFaceView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var responsive: NotchResponsiveLayoutService

    @State private var tab: UtilitiesTab = .home

    private var layoutClass: NotchLayoutClass { responsive.current.layoutClass }

    var body: some View {
        // Utilities is the sole root workspace when Agents is disabled: the tab bar
        // sits near the top content inset and the content follows immediately, with
        // no leftover selector- or title-height spacer.
        VStack(spacing: 4) {
            AdaptiveTabBar(selection: $tab,
                           labelMode: responsive.current.resolvedTabLabels,
                           layoutClass: layoutClass)
            content
        }
        .padding(.top, appState.agentsEnabled ? 4 : 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            tab = UtilitiesTab(rawValue: settings.settings.lastUtilitiesTab) ?? .home
            applyTabHeight()
        }
        .onChange(of: tab) { _, new in
            settings.settings.lastUtilitiesTab = new.rawValue
            applyTabHeight()
        }
    }

    private func applyTabHeight() {
        var h = EditorialHomeLayout.contentHeight(tab: tab.rawValue, layoutClass: layoutClass)
        if tab == .home { h += settings.settings.homeLayoutPreset.heightDelta }   // density preset
        responsive.utilitiesContentHeight = h
        responsive.utilitiesTab = tab.widthProfile
    }

    @ViewBuilder private var content: some View {
        switch tab {
        case .home:
            HomeTabView()
        case .focus:
            PomodoroFocusPage()
        case .files:
            FilesTabView()
        case .more:
            MoreTabView()
        }
    }
}

/// Files/More group tab: enabled modules of the group as widgets on the grid.
struct GroupTabView: View {
    let group: ModuleGroup
    @EnvironmentObject private var registry: ModuleRegistry

    private var modules: [NotchModule] { registry.modules(in: group) }

    var body: some View {
        if modules.isEmpty {
            CategoryEmpty(prompt: "No \(group.title.lowercased()) modules enabled",
                          action: nil, buttonTitle: nil)
        } else {
            ScrollView { HomeGrid(modules: modules) }
        }
    }
}

/// More tab: a customizable dashboard of More-eligible built-in + community
/// modules, with its own module library. Never opens Home customization.
struct MoreTabView: View {
    var body: some View { MoreDashboardView() }
}

/// Adaptive tab bar: full labels on regular/spacious, icons on compact, with an
/// overflow "More" always present. VoiceOver labels preserved.
struct AdaptiveTabBar: View {
    @Binding var selection: UtilitiesTab
    let labelMode: TabLabelMode
    let layoutClass: NotchLayoutClass

    var body: some View {
        HStack(spacing: 4) {
            ForEach(UtilitiesTab.allCases) { t in
                Button { selection = t } label: { chip(t) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t.fullTitle)
            }
        }
        .padding(.horizontal, 12)
    }

    /// Pure decision (unit-testable): should a tab show its text label?
    static func showsLabel(_ t: UtilitiesTab, mode: TabLabelMode, layoutClass: NotchLayoutClass) -> Bool {
        switch mode {
        case .iconsOnly: return t == .home || t == .more
        case .iconsAndLabels: return true
        case .automatic: return layoutClass != .compact || t == .home || t == .more
        }
    }

    private func chip(_ t: UtilitiesTab) -> some View {
        let active = selection == t
        let showLabel = Self.showsLabel(t, mode: labelMode, layoutClass: layoutClass)
        return HStack(spacing: 4) {
            Image(systemName: t.icon).font(.system(size: 10, weight: .medium))
            if showLabel { Text(t.title).font(.system(size: 11, weight: .semibold)) }
        }
        .padding(.horizontal, showLabel ? 9 : 7).padding(.vertical, 4)
        .background(active ? DesignTokens.Palette.cardFillHover : Color.clear, in: Capsule())
        .foregroundStyle(active ? DesignTokens.Palette.primaryText : DesignTokens.Palette.tertiaryText)
    }
}

/// Home uses the stable built-in editorial layout and its dedicated editor.
struct HomeTabView: View {
    @State private var showingHomeCustomization = false

    var body: some View {
        VStack(spacing: 4) {
            header
            HomeEditorialView(onCustomize: { showingHomeCustomization = true })
        }
        .sheet(isPresented: $showingHomeCustomization) {
            HomeCustomizationView()
        }
        // The visual "Home" title is removed (the tab bar already identifies the
        // page); the semantic page title is preserved for VoiceOver.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(UtilitiesTab.home.title))
    }

    /// One consistent entry point for the dedicated Home editor.
    private var header: some View {
        HStack(spacing: 8) {
            Spacer()
            headerBtn("Customize") { showingHomeCustomization = true }
        }
        .padding(.horizontal, 12)
    }

    private func headerBtn(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(DesignTokens.Palette.cardFillHover, in: Capsule())
            .foregroundStyle(DesignTokens.Palette.secondaryText)
    }
}

/// A category tab: enabled modules of one category as dashboard cards.
struct CategoryTabView: View {
    let category: ModuleCategory
    @EnvironmentObject private var registry: ModuleRegistry

    private var modules: [NotchModule] {
        registry.libraryModules.filter { $0.category == category }
    }

    var body: some View {
        if modules.isEmpty {
            CategoryEmpty(prompt: "No \(category.title.lowercased()) modules enabled",
                          action: nil, buttonTitle: nil)
        } else {
            ScrollView { HomeGrid(modules: modules) }
        }
    }
}

struct CategoryEmpty: View {
    let prompt: String
    let action: (() -> Void)?
    let buttonTitle: String?
    var body: some View {
        VStack(spacing: 8) {
            Text(prompt).font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
            if let action, let buttonTitle {
                Button(buttonTitle, action: action)
                    .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(DesignTokens.Palette.cardFillHover, in: Capsule())
                    .foregroundStyle(DesignTokens.Palette.primaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Greedy 4-column reflow of dashboard cards.
struct HomeGrid: View {
    let modules: [NotchModule]
    @EnvironmentObject private var registry: ModuleRegistry

    private struct Row: Identifiable { let id = UUID(); var items: [NotchModule] }

    private var rows: [Row] {
        let spans = modules.map { registry.size(for: $0).columnSpan }
        return DashboardPacking.rows(spans: spans, columns: 4)
            .map { Row(items: $0.map { modules[$0] }) }
    }

    var body: some View {
        GeometryReader { geo in
            let unit = (geo.size.width - 12 * 2 - 10 * 3) / 4
            VStack(spacing: 10) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        ForEach(row.items, id: \.id) { module in
                            let size = registry.size(for: module)
                            DashboardCardContainer(module: module, size: size)
                                .frame(width: cardWidth(size, unit: unit), height: size.height)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12).padding(.bottom, 8)
        }
        .frame(minHeight: totalHeight)
    }

    private func cardWidth(_ size: ModuleDashboardSize, unit: CGFloat) -> CGFloat {
        let span = CGFloat(size.columnSpan)
        return unit * span + 10 * (span - 1)
    }
    private var totalHeight: CGFloat {
        rows.reduce(0) { $0 + (($1.items.map { registry.size(for: $0).height }.max() ?? 96) + 10) }
    }
}

/// A Home card + discreet expand-to-Focus affordance.
struct DashboardCardContainer: View {
    let module: NotchModule
    let size: ModuleDashboardSize
    @EnvironmentObject private var appState: AppState
    @State private var hovering = false

    var body: some View {
        module.makeDashboardCard(size: size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background(DesignTokens.Palette.cardFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(DesignTokens.Palette.hairline, lineWidth: 0.6))
            .overlay(alignment: .topTrailing) {
                if hovering {
                    Button { appState.focusModule(module.id) } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 9, weight: .semibold)).padding(5)
                            .background(.black.opacity(0.4), in: Circle())
                            .foregroundStyle(DesignTokens.Palette.primaryText)
                    }
                    .buttonStyle(.plain).padding(5)
                }
            }
            .onHover { hovering = $0 }
    }
}
