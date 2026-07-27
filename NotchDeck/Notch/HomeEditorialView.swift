import SwiftUI

/// The editorial Home composition: one full-height row on regular/spacious, two
/// pages on compact, with subtle vertical dividers between zones. Not a generic
/// grid — Note / Now Playing / File Shelf / Mirror get intentional, distinct
/// regions, with Mirror always rightmost by default.
struct HomeEditorialView: View {
    var minimal = false
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var responsive: NotchResponsiveLayoutService
    @EnvironmentObject private var dashboard: DashboardModel
    @EnvironmentObject private var appState: AppState
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    @State private var page = 0

    private var layoutClass: NotchLayoutClass { responsive.current.layoutClass }

    /// Enabled built-in Home modules in the configured order, minus hidden.
    ///
    /// This is a strict WHITELIST of enabled built-in Home-group ids: any stale
    /// persisted id that is not a current built-in Home module — Community
    /// (e.g. `community.system-pulse`), workspace or obsolete — is filtered out
    /// defensively and can never render on Home.
    private var order: [String] {
        let base = settings.settings.editorialOrder ?? EditorialHomeLayout.defaultOrder
        let enabledHome = Set(registry.modules(in: .home).map(\.id))
        var ids = base.filter { enabledHome.contains($0) && !settings.settings.editorialHidden.contains($0) }
        // Append any enabled built-in home modules not in the default order.
        for id in registry.modules(in: .home).map(\.id) where !ids.contains(id) { ids.append(id) }
        if minimal { ids = Array(ids.prefix(2)) }
        return ids
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
                .onChange(of: result.pageCount) { _, c in syncPage(pageCount: c) }
            }
            if pageCountForOrder > 1 { pager }
        }
        // Preset-driven edge insets: leading before the first module, a larger
        // trailing after the Mirror, and bottom breathing room. Compact/Balanced/
        // Spacious produce visibly distinct geometry (animated on change).
        .padding(.leading, tokens.leadingInset)
        .padding(.trailing, tokens.trailingInset)
        .padding(.bottom, tokens.bottomBreathing)
        .animation(.easeInOut(duration: 0.22), value: settings.settings.homeLayoutPreset)
        .sheet(isPresented: Binding(get: { dashboard.customizing },
                                    set: { dashboard.customizing = $0 })) {
            HomeCustomizationView()
        }
    }

    private var pageCountForOrder: Int {
        // Two pages when compact or when a regular row can't fit minimums.
        layoutClass == .compact ? 2 :
            (EditorialHomeLayout.requiresPaging(order: order, ratios: classRatios,
                minWidths: EditorialHomeLayout.minWidths, contentWidth: responsive.current.panelWidth - 16,
                layoutClass: layoutClass) ? 2 : 1)
    }

    /// Semantic customize row: reorder, width, hide, restore. No pixel resizing.
    private var customizePanel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(order.enumerated()), id: \.element) { idx, id in
                    HStack(spacing: 4) {
                        Text(registry.module(id: id)?.displayName ?? id).font(.system(size: 9, weight: .medium))
                        Button { move(id, by: -1) } label: { Image(systemName: "chevron.left").font(.system(size: 8)) }.buttonStyle(.plain)
                        Button { move(id, by: 1) } label: { Image(systemName: "chevron.right").font(.system(size: 8)) }.buttonStyle(.plain)
                        Menu {
                            ForEach(EditorialZoneWidth.allCases) { w in
                                Button(w.label) { settings.settings.editorialWidths[id] = w }
                            }
                        } label: { Image(systemName: "arrow.left.and.right").font(.system(size: 8)) }
                            .menuStyle(.borderlessButton).fixedSize()
                        Button { settings.settings.editorialHidden.append(id) } label: {
                            Image(systemName: "eye.slash").font(.system(size: 8)).foregroundStyle(DesignTokens.Palette.statusFailure)
                        }.buttonStyle(.plain)
                    }
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(DesignTokens.Palette.cardFill, in: Capsule())
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
                Button("Restore") { restoreEditorial() }
                    .buttonStyle(.plain).font(.system(size: 9, weight: .medium))
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(DesignTokens.Palette.cardFillHover, in: Capsule())
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 24)
    }

    private func currentOrder() -> [String] {
        settings.settings.editorialOrder ?? EditorialHomeLayout.defaultOrder
    }
    private func move(_ id: String, by delta: Int) {
        var ids = order
        guard let i = ids.firstIndex(of: id) else { return }
        let j = max(0, min(ids.count - 1, i + delta))
        ids.swapAt(i, j)
        settings.settings.editorialOrder = ids
    }
    private func restoreEditorial() {
        settings.settings.editorialOrder = nil
        settings.settings.editorialHidden = []
        settings.settings.editorialWidths = [:]
    }

    @ViewBuilder private func editorialWidget(for id: String) -> some View {
        switch id {
        case "quickNote": EditorialNote()
        case "nowPlaying": EditorialNowPlaying()
        case "fileShelf": EditorialFileShelf()
        case "mirror": EditorialMirror()
        default:
            // Built-in modules only. Community modules are intentionally NOT
            // reachable here — they render in More.
            if let module = registry.module(id: id) { module.makeWidget(size: .medium) }
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
