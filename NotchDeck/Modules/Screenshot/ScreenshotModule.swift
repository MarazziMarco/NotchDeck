import SwiftUI

struct ScreenshotModule: NotchModule {
    let id = "screenshot"
    let displayName = "Screen"
    let iconName = "camera.viewfinder"
    let defaultEnabled = true
    let defaultHomeFavorite = false
    let defaultDashboardSize: ModuleDashboardSize = .medium
    let defaultPriority = 75
    let category: ModuleCategory = .media
    let defaultGroup: ModuleGroup = .files
    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .wide]
    let defaultWidgetSize: DashboardWidgetSize = .medium
    let preferredStyle: DashboardWidgetStyle = .tile

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView { AnyView(ScreenshotWidget(size: .medium)) }
    func makeFocusView() -> AnyView { AnyView(ScreenshotWidget(size: .wide)) }
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(ScreenshotWidget(size: size)) }
}

struct ScreenshotWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: ScreenshotService

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                recIdentity
                Spacer()
                Button { service.captureInteractive() } label: {
                    Image(systemName: "camera").font(.system(size: 11))
                }.buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            if size != .small { thumbnails }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { service.start() }
    }

    private var recIdentity: some View {
        Button { service.toggleRecording() } label: {
            HStack(spacing: 5) {
                ZStack {
                    Circle().strokeBorder(service.isRecording ? DesignTokens.Palette.statusFailure : .white.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 16, height: 16)
                    if service.isRecording {
                        RoundedRectangle(cornerRadius: 1).fill(DesignTokens.Palette.statusFailure).frame(width: 6, height: 6)
                    } else {
                        Circle().fill(DesignTokens.Palette.statusFailure.opacity(0.8)).frame(width: 7, height: 7)
                    }
                }
                Text(service.isRecording ? service.formattedElapsed : "REC")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(service.isRecording ? DesignTokens.Palette.statusFailure : DesignTokens.Palette.secondaryText)
            }
        }.buttonStyle(.plain)
    }

    private var thumbnails: some View {
        HStack(spacing: 4) {
            if service.recent.isEmpty {
                Text("No recent screenshots").font(.system(size: 9)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            } else {
                ForEach(service.recent.prefix(size == .wide ? 4 : 2), id: \.self) { url in
                    if let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 34, height: 24).clipShape(RoundedRectangle(cornerRadius: 4))
                            .onTapGesture { NSWorkspace.shared.open(url) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
