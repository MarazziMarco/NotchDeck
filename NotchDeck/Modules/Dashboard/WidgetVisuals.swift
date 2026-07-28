import SwiftUI

// MARK: Mirror — circular

/// Mirror widget with a visibly circular camera surface (cell stays rectangular,
/// the visible surface is a circle). Tap toggles on/off in normal mode.
struct MirrorWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: MirrorService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 6) {
            circle
            if size == .medium, service.availableCameras.count > 1 {
                Text(service.isEnabled ? "On" : "Off")
                    .font(.system(size: 9)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle())
        .onTapGesture { service.toggle() }
        .task { await service.activateIfEnabled() }
        .onDisappear { service.deactivateForHidden() }
        .help(service.isEnabled ? "Turn Mirror off" : "Turn Mirror on")
    }

    private var circle: some View {
        ZStack {
            if case .running = service.state {
                CameraPreviewView(session: service.session)
                    // Slight zoom (crop via aspect-fill scale) for a better mirror.
                    .scaleEffect(settings.settings.mirrorZoomed ? 1.35 : 1.0)
                    .clipShape(Circle())
            } else {
                Circle().fill(Color.white.opacity(0.05))
                    .overlay(Image(systemName: service.state == .denied ? "video.slash" : "web.camera")
                        .font(.system(size: size == .compact ? 12 : 18))
                        .foregroundStyle(DesignTokens.Palette.tertiaryText))
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))   // reflective rim
        .overlay(alignment: .topLeading) {
            Circle().fill(.white.opacity(0.06)).frame(width: 8, height: 8).blur(radius: 2).offset(x: 6, y: 6)
        }
        .overlay(alignment: .bottomTrailing) {
            if service.isEnabled {
                Circle().fill(DesignTokens.Palette.statusSuccess).frame(width: 6, height: 6).padding(3)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: Pomodoro — tomato / minimal / monochrome

struct PomodoroWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: PomodoroService
    @EnvironmentObject private var settings: SettingsStore

    private var m: PomodoroModel { PomodoroModel(service: service) }
    private var style: PomodoroWidgetStyle { settings.settings.pomodoroWidgetStyle }

    var body: some View {
        VStack(spacing: 6) {
            body_shape
            if size == .wide { controls }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(6)
    }

    private var accent: Color {
        switch style {
        case .monochrome: return .white.opacity(0.85)
        default: return m.phase.tint
        }
    }

    @ViewBuilder private var body_shape: some View {
        ZStack {
            switch style {
            case .minimal:
                ProgressRing(progress: m.progress, lineWidth: 4, tint: accent)
            case .monochrome:
                ProgressRing(progress: m.progress, lineWidth: 4, tint: accent)
            case .tomato:
                TomatoShape(progress: m.progress, accent: accent)
            }
            Text(m.time)
                .font(.system(size: size == .compact ? 13 : 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .frame(width: size == .compact ? 44 : 64, height: size == .compact ? 44 : 64)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            btn(m.isRunning ? "pause.fill" : "play.fill") {
                if m.isRunning { service.pause() } else if m.phase == .idle { service.start() } else { service.resume() }
            }
            btn("forward.fill") { service.skip() }
            btn("arrow.counterclockwise") { service.reset() }
        }
    }
    private func btn(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 11)) }
            .buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.secondaryText)
    }
}

/// A restrained tomato-inspired silhouette: rounded body, flattened top, a small
/// leaf crown, progress traced around the body outline.
struct TomatoShape: View {
    let progress: Double
    let accent: Color
    var body: some View {
        ZStack {
            Circle().fill(accent.opacity(0.14))
            Circle().trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            // Leaf crown.
            Image(systemName: "leaf.fill")
                .font(.system(size: 8)).foregroundStyle(accent.opacity(0.9))
                .rotationEffect(.degrees(-20))
                .offset(y: -22)
        }
    }
}

// MARK: Now Playing — album-art geometry

struct NowPlayingWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: NowPlayingService

    var body: some View {
        Group {
            if size == .compact { compact } else { horizontal }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .task { service.start() }
    }

    private var artwork: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(LinearGradient(colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(Image(systemName: "music.note").font(.system(size: 16))
                .foregroundStyle(DesignTokens.Palette.secondaryText))
            .overlay(alignment: .bottomTrailing) {
                if service.track?.isPlaying == true { Equalizer().padding(4) }
            }
            .aspectRatio(1, contentMode: .fit)
    }

    private var compact: some View {
        HStack(spacing: 6) {
            artwork.frame(width: 30, height: 30)
            Button { service.playPause() } label: {
                Image(systemName: service.track?.isPlaying == true ? "pause.fill" : "play.fill")
                    .font(.system(size: 12))
            }.buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.primaryText)
        }
    }

    private var horizontal: some View {
        HStack(spacing: 10) {
            artwork.frame(width: size == .medium ? 44 : 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.track?.title ?? "Nothing playing")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                Text(service.track?.artist ?? (service.providerAvailable ? "" : "Open Music or Spotify"))
                    .font(.system(size: 10)).lineLimit(1).foregroundStyle(DesignTokens.Palette.secondaryText)
                HStack(spacing: 12) {
                    tb("backward.fill") { service.previous() }
                    tb(service.track?.isPlaying == true ? "pause.fill" : "play.fill") { service.playPause() }
                    tb("forward.fill") { service.next() }
                }.padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }
    private func tb(_ icon: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 11)) }
            .buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.primaryText)
    }
}

/// Tiny animated equalizer shown while playing (respects Reduce Motion).
struct Equalizer: View {
    @Environment(\.accessibilityReduceMotion) private var reduce
    @State private var phase = false
    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<3, id: \.self) { i in
                Capsule().fill(DesignTokens.Palette.statusSuccess)
                    .frame(width: 2, height: reduce ? 6 : (phase ? 8 : 4) + CGFloat(i))
            }
        }
        .onAppear { if !reduce { withAnimation(.easeInOut(duration: 0.5).repeatForever()) { phase = true } } }
    }
}

// MARK: Clipboard — layered sheet

struct ClipboardWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: ClipboardService

    var body: some View {
        if size == .wide || size == .large {
            ClipboardExpandedView()
        } else {
            ZStack {
                // Layered-paper detail.
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.04))
                    .offset(x: 3, y: 3).scaleEffect(0.96)
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.06))
                    .offset(x: 1.5, y: 1.5).scaleEffect(0.98)
                VStack(alignment: .leading, spacing: 4) {
                    HStack { Image(systemName: "doc.on.clipboard").font(.system(size: 11))
                        Text("\(service.history.items.count)").font(.system(size: 12, weight: .semibold))
                        Spacer() }
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                    ForEach(Array(service.history.items.prefix(size == .medium ? 3 : 1))) { item in
                        Text(item.preview).font(.system(size: 10)).lineLimit(1)
                            .foregroundStyle(DesignTokens.Palette.primaryText)
                    }
                    if service.history.items.isEmpty {
                        Text("Nothing copied").font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    }
                    Spacer(minLength: 0)
                }
                .padding(8)
            }
        }
    }
}

// MARK: File Shelf — tray

struct FileShelfWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var store: FileShelfStore
    @State private var targeted = false

    var body: some View {
        VStack(spacing: 4) {
            HStack { Image(systemName: "tray.full").font(.system(size: 11))
                Text("Shelf").font(.system(size: 11, weight: .semibold))
                Spacer()
                if !store.items.isEmpty { Text("\(store.items.count)").font(.system(size: 10)) }
            }
            .foregroundStyle(DesignTokens.Palette.secondaryText)
            tray
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            if ShelfDrag.isInternal(providers) { return true }
            for p in providers where p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { store.add(urls: [url]) } }
                }
            }
            return true
        }
    }

    private var tray: some View {
        ZStack(alignment: .bottom) {
            // Recessed tray lip.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.black.opacity(0.35))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(targeted ? DesignTokens.Palette.statusRunning : .white.opacity(0.08),
                                  lineWidth: targeted ? 1.5 : 1))
            if store.items.isEmpty {
                Text("Drop files").font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .padding(.bottom, 8)
            } else {
                HStack(spacing: 6) {
                    ForEach(store.items.prefix(size == .wide ? 5 : 3)) { item in
                        Image(nsImage: item.icon).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 22, height: 22).opacity(item.isMissing ? 0.4 : 1)
                    }
                    Spacer(minLength: 0)
                }.padding(8)
            }
        }
    }
}

// MARK: Quick Note — paper

/// A true post-it: warm coloured paper, ink text, a slight fold + shadow.
struct QuickNoteWidget: View {
    let size: DashboardWidgetSize
    @EnvironmentObject private var service: QuickNoteService
    @EnvironmentObject private var settings: SettingsStore

    private var paperColor: NotePaperColor {
        settings.settings.resolvedNotePaperColor
    }
    private var paperStyle: PaperStyleIntensity { settings.settings.paperStyleIntensity }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Image(systemName: "pencil.and.scribble").font(.system(size: 10))
                Text("Note").font(.system(size: 11, weight: .semibold)); Spacer() }
                .foregroundStyle(paperColor.inkColor.opacity(0.7))
            if size == .small {
                Text(service.isEmpty ? "Tap to jot…" : service.firstLine)
                    .font(.system(size: 11, weight: .medium)).lineLimit(2)
                    .foregroundStyle(
                        service.isEmpty
                            ? paperColor.inkColor.opacity(0.45)
                            : paperColor.inkColor
                    )
            } else {
                TextEditor(text: $service.text)
                    .font(.system(size: 12, weight: .medium)).scrollContentBackground(.hidden)
                    .foregroundStyle(paperColor.inkColor)
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [paperColor.color, paperColor.color.opacity(0.92)],
                                         startPoint: .top, endPoint: .bottom))
                Rectangle().fill(paperColor.inkColor.opacity(0.12)).frame(height: 1).padding(.top, 24)
                    .frame(maxHeight: .infinity, alignment: .top)
                if paperStyle.showsFold {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 14, y: 0)); p.addLine(to: CGPoint(x: 0, y: 14))
                    }.fill(paperColor.inkColor.opacity(0.10)).frame(width: 14, height: 14)
                }
            }
        }
        .shadow(color: .black.opacity(0.35), radius: paperStyle.shadow, y: paperStyle.shadow / 2)
    }
}
