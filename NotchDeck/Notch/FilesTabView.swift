import SwiftUI

/// Files tab: a practical workspace. Default editorial composition = Clipboard
/// main left column + Downloads/Screen stacked right column. Grid style falls
/// back to the generic widget grid over the Files-group modules.
struct FilesTabView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var responsive: NotchResponsiveLayoutService
    @EnvironmentObject private var dashboard: DashboardModel

    private var layoutClass: NotchLayoutClass { responsive.current.layoutClass }
    private var style: HomeCompositionStyle {
        settings.settings.filesCompositionByClass[layoutClass.rawValue] ?? .editorial
    }

    var body: some View {
        VStack(spacing: 4) {
            header
            if style == .grid {
                let modules = registry.modules(in: .files)
                if modules.isEmpty {
                    CategoryEmpty(prompt: "No files modules enabled", action: nil, buttonTitle: nil)
                } else { ScrollView { HomeGrid(modules: modules) } }
            } else {
                FilesEditorialView()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Files").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Spacer()
            if dashboard.customizing {
                Menu("Split") {
                    ForEach(FilesRightSplit.allCases) { s in
                        Button(s.label) { settings.settings.filesRightSplit = s }
                    }
                }.font(.system(size: 10)).menuStyle(.borderlessButton).fixedSize()
                Menu("Clip \(settings.settings.clipboardPreviewCount)") {
                    ForEach([2, 3, 4], id: \.self) { n in Button("\(n) items") { settings.settings.clipboardPreviewCount = n } }
                }.font(.system(size: 10)).menuStyle(.borderlessButton).fixedSize()
                Toggle("Src", isOn: $settings.settings.filesShowSourceApp).toggleStyle(.button).controlSize(.mini)
                Toggle("Thumbs", isOn: $settings.settings.screenShowThumbnails).toggleStyle(.button).controlSize(.mini)
                Menu(style.label) {
                    Button("Editorial") { settings.settings.filesCompositionByClass[layoutClass.rawValue] = .editorial }
                    Button("Grid") { settings.settings.filesCompositionByClass[layoutClass.rawValue] = .grid }
                }.font(.system(size: 10)).menuStyle(.borderlessButton).fixedSize()
                btn("Reset") { resetFiles() }
                btn("Done") { dashboard.customizing = false }
            } else {
                btn("Customize") { dashboard.customizing = true }
            }
        }
        .padding(.horizontal, 12)
    }

    private func btn(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(t, action: a).buttonStyle(.plain).font(.system(size: 10, weight: .medium))
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(DesignTokens.Palette.cardFillHover, in: Capsule())
            .foregroundStyle(DesignTokens.Palette.secondaryText)
    }

    private func resetFiles() {
        settings.settings.filesRightSplit = .balanced
        settings.settings.clipboardPreviewCount = 3
        settings.settings.filesShowSourceApp = true
        settings.settings.screenShowThumbnails = true
        settings.settings.filesCompositionByClass[layoutClass.rawValue] = .editorial
    }
}

/// Renders the editorial Files frames with subtle separators + compact paging.
struct FilesEditorialView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var responsive: NotchResponsiveLayoutService
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiate

    @State private var page = 0
    private var layoutClass: NotchLayoutClass { responsive.current.layoutClass }
    private var showDividers: Bool { settings.settings.showHomeDividers && !differentiate }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let files = FilesEditorialLayout.layout(
                    contentSize: geo.size, layoutClass: layoutClass,
                    split: settings.settings.filesRightSplit, page: page,
                    dividerWidth: showDividers ? 1 : 0)
                ZStack(alignment: .topLeading) {
                    zone(FilesEditorialLayout.clipboardID, files) { ClipboardFilesWidget() }
                    zone(FilesEditorialLayout.downloadsID, files) { DownloadsFilesWidget() }
                    zone(FilesEditorialLayout.screenID, files) { ScreenFilesWidget() }
                    if showDividers { separators(files, size: geo.size) }
                }
                .onAppear { page = min(page, files.pageCount - 1) }
            }
            if layoutClass == .compact { pager }
        }
        .padding(.horizontal, 10)
    }

    @ViewBuilder private func zone<V: View>(_ id: String, _ files: FilesLayout, @ViewBuilder _ content: () -> V) -> some View {
        if let f = files.frame(id) {
            content()
                .frame(width: f.width, height: f.height)
                .position(x: f.midX, y: f.midY)
        }
    }

    /// Vertical separator between the two columns + horizontal between right stack.
    private func separators(_ files: FilesLayout, size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            if let clip = files.frame(FilesEditorialLayout.clipboardID),
               files.frame(FilesEditorialLayout.downloadsID) != nil {
                LinearGradient(colors: [.clear, .white.opacity(0.09), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(width: 1, height: size.height - 12)
                    .position(x: clip.maxX + 6, y: size.height / 2)
            }
            if let dl = files.frame(FilesEditorialLayout.downloadsID),
               let sc = files.frame(FilesEditorialLayout.screenID) {
                LinearGradient(colors: [.clear, .white.opacity(0.09), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: dl.width - 8, height: 1)
                    .position(x: dl.midX, y: (dl.maxY + sc.minY) / 2)
            }
        }
    }

    private var pager: some View {
        HStack(spacing: 5) {
            ForEach(0..<2, id: \.self) { i in
                Circle().fill(i == page ? DesignTokens.Palette.primaryText : DesignTokens.Palette.tertiaryText)
                    .frame(width: 5, height: 5).onTapGesture { page = i }
            }
        }.padding(.bottom, 2)
    }
}
