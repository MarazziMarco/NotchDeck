import SwiftUI

struct NowPlayingModule: NotchModule {
    let id = "nowPlaying"
    let displayName = "Now Playing"
    let iconName = "music.note"
    let defaultEnabled = true
    let defaultHomeFavorite = false
    let defaultDashboardSize: ModuleDashboardSize = .medium
    let supportedSizes: [ModuleDashboardSize] = [.small, .medium, .large]
    let defaultPriority = 60
    let defaultGroup: ModuleGroup = .home
    let category: ModuleCategory = .media

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView {
        AnyView(NowPlayingCard(size: size))
    }
    func makeFocusView() -> AnyView { AnyView(NowPlayingFocusView()) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.compact, .small, .medium, .wide]
    let defaultWidgetSize: DashboardWidgetSize = .medium
    let preferredStyle: DashboardWidgetStyle = .custom
    let canLiveActivity = true
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(NowPlayingWidget(size: size)) }
}

struct NowPlayingCard: View {
    let size: ModuleDashboardSize
    @EnvironmentObject private var service: NowPlayingService

    var body: some View {
        Group {
            if size == .small {
                ModuleSummaryCard(icon: "music.note", title: "Now Playing", value: nil,
                                  subtitle: service.track?.title ?? "Nothing playing",
                                  tint: .neutral, compact: true)
            } else {
                content
            }
        }
        .task { service.start() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Now Playing", accessory: service.track?.app)
            if let track = service.track {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                    Text(track.artist).font(.system(size: 10)).lineLimit(1)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
                transport
            } else {
                Text(service.providerAvailable ? "Nothing playing" : "Open Music or Spotify")
                    .font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .dashboardCard()
    }

    private var transport: some View {
        HStack(spacing: 14) {
            control("backward.fill") { service.previous() }
            control(service.track?.isPlaying == true ? "pause.fill" : "play.fill") { service.playPause() }
            control("forward.fill") { service.next() }
        }
        .frame(maxWidth: .infinity)
    }

    private func control(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 12)) }
            .buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.primaryText)
    }
}

struct NowPlayingFocusView: View {
    @EnvironmentObject private var service: NowPlayingService

    var body: some View {
        VStack(spacing: 14) {
            Label("Now Playing", systemImage: "music.note")
                .font(.headline).foregroundStyle(DesignTokens.Palette.primaryText)
            if let track = service.track {
                Image(systemName: "music.note").font(.system(size: 40))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Text(track.title).font(.title3).fontWeight(.semibold).lineLimit(1)
                Text(track.artist).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                Text(track.app).font(.caption2).foregroundStyle(.tertiary)
                HStack(spacing: 24) {
                    big("backward.fill") { service.previous() }
                    big(track.isPlaying ? "pause.circle.fill" : "play.circle.fill") { service.playPause() }
                    big("forward.fill") { service.next() }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "music.note.list").font(.largeTitle).foregroundStyle(.tertiary)
                    Text(service.providerAvailable ? "Nothing playing" : "No supported player running")
                        .font(.callout).foregroundStyle(.secondary)
                    Text("Supports Music and Spotify via automation. System-wide now-playing needs private APIs and is intentionally not used.")
                        .font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Metrics.contentPadding)
        .task { service.start() }
    }

    private func big(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 26)) }
            .buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.primaryText)
    }
}
