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
        VStack(spacing: 6) {
            AdaptiveTabBar(selection: $tab,
                           labelMode: responsive.current.resolvedTabLabels,
                           layoutClass: layoutClass)
            content
        }
        .padding(.top, 6)
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

/// More tab: library entry + customization + future modules.
struct MoreTabView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 10) {
            CategoryEmpty(prompt: "Manage modules, add to Home, and configure",
                          action: { appState.showingModuleLibrary = true },
                          buttonTitle: "Open Module Library")
            if !registry.modules(in: .more).isEmpty {
                ScrollView { HomeGrid(modules: registry.modules(in: .more)) }
            }
        }
    }
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

/// Home tab — favorites resolved for the current layout (max modules, min-size
/// aware). Overflow modules are moved off Home, never shrunk to tiny.
struct HomeTabView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var responsive: NotchResponsiveLayoutService
    @EnvironmentObject private var dashboard: DashboardModel

    @State private var page = 0

    private var layoutClass: NotchLayoutClass { responsive.current.layoutClass }
    private var columns: Int { DashboardGrid.columns(for: layoutClass) }
    private var result: GridSolver.Result { dashboard.resolved(for: layoutClass) }

    @EnvironmentObject private var settings: SettingsStore

    private var style: HomeCompositionStyle {
        settings.settings.homeCompositionByClass[layoutClass.rawValue] ?? .editorial
    }

    var body: some View {
        VStack(spacing: 4) {
            header
            switch style {
            case .editorial: HomeEditorialView()
            case .minimal: HomeEditorialView(minimal: true)
            case .grid:
                if result.cells.isEmpty { empty } else { grid }
                if result.pageCount > 1 { pager }
            }
        }
        .onChange(of: dashboard.customizing) { _, c in appState.isCustomizingDashboard = c }
        .onDisappear { appState.isCustomizingDashboard = false }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Home").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            if dashboard.customizing {
                Text("· \(layoutClass.rawValue.capitalized)")
                    .font(.system(size: 9)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
            Spacer()
            if dashboard.customizing {
                Menu(style.label) {
                    ForEach(HomeCompositionStyle.allCases) { s in
                        Button(s.label) { settings.settings.homeCompositionByClass[layoutClass.rawValue] = s }
                    }
                }.font(.system(size: 10.5)).menuStyle(.borderlessButton).fixedSize()
                headerBtn("Add") { appState.showingModuleLibrary = true }
                headerBtn("Done") { dashboard.customizing = false }
            } else {
                headerBtn("Customize") { dashboard.customizing = true }
            }
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

    private var grid: some View {
        GeometryReader { geo in
            let cellW = geo.size.width / CGFloat(columns)
            let rowH: CGFloat = 46
            let cells = result.cells.filter { $0.page == page }
            ZStack(alignment: .topLeading) {
                if dashboard.customizing { alignmentGrid(cols: columns, cellW: cellW, rowH: rowH, in: geo.size) }
                ForEach(cells) { cell in
                    if let module = dashboard.module(id: cell.id) {
                        WidgetHost(module: module,
                                   size: sizeFor(cell),
                                   customizing: dashboard.customizing,
                                   layoutClass: layoutClass,
                                   onDrop: { order in dashboard.move(cell.id, toOrder: order, for: layoutClass) })
                            .frame(width: cellW * CGFloat(cell.w) - 8, height: rowH * CGFloat(cell.h) - 8)
                            .position(x: cellW * (CGFloat(cell.col) + CGFloat(cell.w) / 2),
                                      y: rowH * (CGFloat(cell.row) + CGFloat(cell.h) / 2))
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 8)
    }

    private func sizeFor(_ cell: GridCell) -> DashboardWidgetSize {
        dashboard.placements(for: layoutClass).first { $0.moduleID == cell.id }?.size ?? .small
    }

    private func alignmentGrid(cols: Int, cellW: CGFloat, rowH: CGFloat, in size: CGSize) -> some View {
        Path { p in
            for c in 0...cols { let x = cellW * CGFloat(c); p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: size.height)) }
            for r in 0...Int(size.height / rowH) { let y = rowH * CGFloat(r); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: size.width, y: y)) }
        }
        .stroke(.white.opacity(0.06), lineWidth: 0.5)
    }

    private var pager: some View {
        HStack(spacing: 5) {
            ForEach(0..<result.pageCount, id: \.self) { i in
                Circle().fill(i == page ? DesignTokens.Palette.primaryText : DesignTokens.Palette.tertiaryText)
                    .frame(width: 5, height: 5)
                    .onTapGesture { page = i }
            }
        }
        .padding(.bottom, 4)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2").font(.system(size: 26))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            Text("No widgets yet").font(.callout).foregroundStyle(DesignTokens.Palette.secondaryText)
            Button("Add widgets") { appState.showingModuleLibrary = true }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(DesignTokens.Palette.cardFillHover, in: Capsule())
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hosts a widget: renders the module's distinct-identity widget, adds a
/// silhouette background for tile/sheet styles (circular/custom draw their own),
/// and — in Customize mode — a drag handle, resize menu and remove control.
/// Normal-mode functional controls (Pomodoro/music) stay usable because dragging
/// is only enabled via the handle in customize mode.
struct WidgetHost: View {
    let module: NotchModule
    let size: DashboardWidgetSize
    let customizing: Bool
    let layoutClass: NotchLayoutClass
    let onDrop: (Int) -> Void

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var dashboard: DashboardModel
    @State private var hovering = false

    private var wantsBackground: Bool {
        switch module.preferredStyle {
        case .circular, .custom: return false
        default: return true
        }
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if wantsBackground {
                    RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                        .fill(DesignTokens.Palette.cardFill)
                        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                            .strokeBorder(DesignTokens.Palette.hairline, lineWidth: 0.6))
                }
            }
            .overlay(alignment: .topTrailing) { if !customizing && hovering { expandButton } }
            .overlay { if customizing { customizeChrome } }
            .onHover { hovering = $0 }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("\(module.displayName) widget, \(size.label), \(layoutClass.rawValue)")
    }

    private var content: some View {
        module.makeWidget(size: size)
            .allowsHitTesting(!customizing)   // disable functional controls while dragging
    }

    private var expandButton: some View {
        Button { appState.focusModule(module.id) } label: {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 9, weight: .semibold)).padding(5)
                .background(.black.opacity(0.4), in: Circle())
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }.buttonStyle(.plain).padding(4)
    }

    private var customizeChrome: some View {
        ZStack {
            RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(DesignTokens.Palette.statusRunning.opacity(0.6),
                              style: StrokeStyle(lineWidth: 1, dash: [4]))
            VStack {
                HStack {
                    // Drag handle (only this initiates the drag).
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 11)).padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                        .onDrag { NSItemProvider(object: module.id as NSString) }
                    Spacer()
                    Button { dashboard.remove(module.id, for: layoutClass) } label: {
                        Image(systemName: "minus.circle.fill").font(.system(size: 12))
                            .foregroundStyle(DesignTokens.Palette.statusFailure)
                    }.buttonStyle(.plain)
                }
                Spacer()
                Menu {
                    ForEach(module.supportedWidgetSizes) { s in
                        Button(s.label) { dashboard.setSize(module.id, s, for: layoutClass) }
                    }
                } label: {
                    Image(systemName: "square.resize").font(.system(size: 10)).padding(4)
                        .background(.black.opacity(0.5), in: Circle())
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                }.menuStyle(.borderlessButton).fixedSize()
            }
            .padding(4)
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            _ = providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                if let draggedID = obj as? String, draggedID != module.id {
                    DispatchQueue.main.async {
                        let placements = dashboard.placements(for: layoutClass)
                        if let targetOrder = placements.first(where: { $0.moduleID == module.id })?.order {
                            dashboard.move(draggedID, toOrder: targetOrder, for: layoutClass)
                        }
                    }
                }
            }
            return true
        }
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
