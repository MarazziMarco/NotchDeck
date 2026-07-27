import SwiftUI

/// The editorial Home composition: one full-height row on regular/spacious, two
/// pages on compact, with subtle vertical dividers between zones. Not a generic
/// grid — Note / Now Playing / File Shelf / Mirror get intentional, distinct
/// regions, with Mirror always rightmost by default.
struct HomeEditorialView: View {
    var onCustomize: () -> Void = {}
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var responsive: NotchResponsiveLayoutService
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    @State private var page = 0

    private var layoutClass: NotchLayoutClass { responsive.current.layoutClass }

    private var definitions: [HomeModuleDefinition] {
        HomeModuleEligibility.definitions(from: registry.allModules)
    }

    /// Stable eligible built-ins in the persisted order, filtered by the same
    /// authoritative visibility source used by Customize Home.
    private var order: [String] {
        HomeLayoutNormalizer.visibleOrder(
            in: settings.settings, definitions: definitions)
    }

    private var showDividers: Bool {
        settings.settings.showHomeDividers && !differentiate
    }

    /// Active preset geometry tokens (source of truth for Home spacing).
    private var tokens: HomeGeometryTokens { settings.settings.homeLayoutPreset.tokens }

    /// Class-adaptive ratios scaled by each zone's semantic width.
    private var classRatios: [String: CGFloat] {
        var r = EditorialHomeLayout.ratios(for: layoutClass)
        for (id, width) in settings.settings.editorialWidths {
            r[id] = (r[id] ?? 0.25) * width.multiplier
        }
        return r
    }

    var body: some View {
        Group {
            if order.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "house")
                        .font(.system(size: 25))
                        .foregroundStyle(DesignTokens.Palette.tertiaryText)
                    Text(HomeEmptyState.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                    Text(HomeEmptyState.message)
                        .font(.system(size: 11))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                    Button("Customize Home", action: onCustomize)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel("Customize Home")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        let paged = EditorialHomeLayout.requiresPaging(
                            order: order, ratios: classRatios, minWidths: EditorialHomeLayout.minWidths,
                            contentWidth: geo.size.width, layoutClass: layoutClass)
                        let result = EditorialHomeLayout.layout(
                            order: order, ratios: classRatios, contentSize: geo.size,
                            layoutClass: layoutClass, page: page, paged: paged,
                            dividerWidth: showDividers ? 1 : 0)
                        ZStack(alignment: .topLeading) {
                            ForEach(result.zones) { zone in
                                editorialWidget(for: zone.moduleID)
                                    .frame(width: zone.frame.width, height: zone.frame.height)
                                    .position(x: zone.frame.midX, y: zone.frame.midY)
                                    .accessibilityLabel(Text("\(registry.module(id: zone.moduleID)?.displayName ?? zone.moduleID) zone"))
                            }
                            if showDividers { dividers(zones: result.zones, height: geo.size.height) }
                        }
                        .onAppear { syncPage(pageCount: result.pageCount) }
                        .onChange(of: result.pageCount) { _, count in syncPage(pageCount: count) }
                    }
                    if pageCountForOrder > 1 { pager }
                }
            }
        }
        // Preset-driven edge insets: leading before the first module, a larger
        // trailing after the Mirror, and bottom breathing room. Compact/Balanced/
        // Spacious produce visibly distinct geometry (animated on change).
        .padding(.leading, tokens.leadingInset)
        .padding(.trailing, tokens.trailingInset)
        .padding(.bottom, tokens.bottomBreathing)
        .animation(.easeInOut(duration: 0.22), value: settings.settings.homeLayoutPreset)
    }

    private var pageCountForOrder: Int {
        // Two pages when compact or when a regular row can't fit minimums.
        layoutClass == .compact ? 2 :
            (EditorialHomeLayout.requiresPaging(order: order, ratios: classRatios,
                minWidths: EditorialHomeLayout.minWidths, contentWidth: responsive.current.panelWidth - 16,
                layoutClass: layoutClass) ? 2 : 1)
    }

    @ViewBuilder private func editorialWidget(for id: String) -> some View {
        switch id {
        case "quickNote": EditorialNote()
        case "nowPlaying": EditorialNowPlaying()
        case "fileShelf": EditorialFileShelf()
        case "mirror": EditorialMirror()
        default:
            if let module = registry.module(id: id) {
                let size = HomeLayoutNormalizer.size(
                    id, in: settings.settings, definitions: definitions)?.dashboardSize
                    ?? module.defaultDashboardSize
                module.makeDashboardCard(size: size)
            }
        }
    }

    /// Faded vertical separators sitting in the gaps between zones.
    private func dividers(zones: [EditorialZone], height: CGFloat) -> some View {
        ForEach(zones.dropLast().indices, id: \.self) { i in
            let x = zones[i].frame.maxX + 6
            LinearGradient(colors: [.clear, .white.opacity(0.09), .white.opacity(0.09), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: 1, height: height - 12)
                .position(x: x, y: height / 2)
        }
    }

    private var pager: some View {
        HStack(spacing: 5) {
            ForEach(0..<pageCountForOrder, id: \.self) { i in
                Circle().fill(i == page ? DesignTokens.Palette.primaryText : DesignTokens.Palette.tertiaryText)
                    .frame(width: 5, height: 5).onTapGesture { setPage(i) }
            }
        }
        .padding(.bottom, 2)
    }

    private func syncPage(pageCount: Int) {
        let stored = settings.settings.homePageByClass[layoutClass.rawValue] ?? 0
        page = max(0, min(stored, pageCount - 1))
    }
    private func setPage(_ i: Int) {
        page = i
        settings.settings.homePageByClass[layoutClass.rawValue] = i
    }
}

enum HomeEmptyState {
    static let title = "Your Home is empty"
    static let message = "Choose which utilities appear here."
}
