import SwiftUI

// MARK: Clipboard — controlled vertical main module

struct ClipboardFilesWidget: View {
    @EnvironmentObject private var service: ClipboardService
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var appState: AppState

    private var previewCount: Int { max(2, min(4, settings.settings.clipboardPreviewCount)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            searchField
            entries
            Spacer(minLength: 0)
            Button { appState.focusModule("clipboard") } label: {
                Label("Open full history", systemImage: "clock.arrow.circlepath")
                    .font(.system(size: 10, weight: .medium))
            }.buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.statusRunning)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard").font(.system(size: 11))
            Text("Clipboard").font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.primaryText)
            Text("\(service.history.items.count)")
                .font(.system(size: 10, weight: .medium)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            Spacer()
            Button {
                let paused = !settings.settings.clipboardMonitoringPaused
                settings.settings.clipboardMonitoringPaused = paused
                service.isPaused = paused
                if paused { service.stopMonitoring() } else { service.startMonitoring() }
            } label: {
                Image(systemName: settings.settings.clipboardMonitoringPaused ? "play.fill" : "pause.fill")
                    .font(.system(size: 10))
            }.buttonStyle(.plain).help("Pause monitoring")
        }
        .foregroundStyle(DesignTokens.Palette.secondaryText)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(.secondary)
            TextField("Search", text: $service.searchQuery).textFieldStyle(.plain).font(.system(size: 10))
        }
        .padding(5)
        .background(DesignTokens.Palette.cardFill, in: RoundedRectangle(cornerRadius: 7))
    }

    private var entries: some View {
        VStack(spacing: 4) {
            let items = service.filteredItems.prefix(previewCount)
            if items.isEmpty {
                Text(service.searchQuery.isEmpty ? "Nothing copied yet" : "No matches")
                    .font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            } else {
                ForEach(items) { item in row(item) }
            }
        }
    }

    private func row(_ item: ClipboardItem) -> some View {
        Button { service.restore(item) } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol(item)).font(.system(size: 9))
                    .foregroundStyle(DesignTokens.Palette.tertiaryText).frame(width: 12)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.preview).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                    if settings.settings.filesShowSourceApp, let src = item.sourceAppName {
                        Text(src).font(.system(size: 8)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 2).padding(.horizontal, 4)
            .background(DesignTokens.Palette.cardFill, in: RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }
    private func symbol(_ i: ClipboardItem) -> String {
        switch i.kind { case .image: return "photo"; case .url: return "link"; case .fileURL: return "doc"; default: return "text.alignleft" }
    }
}

// MARK: Downloads — upper-right supporting module

struct DownloadsFilesWidget: View {
    @EnvironmentObject private var service: DownloadsService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.down.circle").font(.system(size: 10))
                Text("Downloads").font(.system(size: 11, weight: .semibold))
                Spacer()
                if service.activeCount > 0 {
                    HStack(spacing: 2) { Circle().fill(DesignTokens.Palette.statusRunning).frame(width: 4, height: 4)
                        Text("\(service.activeCount)").font(.system(size: 9, weight: .semibold)) }
                        .foregroundStyle(DesignTokens.Palette.statusRunning)
                }
                Button { service.openFolder() } label: { Image(systemName: "folder").font(.system(size: 9)) }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(DesignTokens.Palette.secondaryText)
            if service.items.isEmpty {
                Text("No recent downloads").font(.system(size: 9)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            } else {
                ForEach(service.items.prefix(3)) { item in
                    HStack(spacing: 5) {
                        Image(systemName: item.isActive ? "arrow.down.circle.fill" : "doc")
                            .font(.system(size: 9))
                            .foregroundStyle(item.isActive ? DesignTokens.Palette.statusRunning : DesignTokens.Palette.tertiaryText)
                        Text(item.name).font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                            .foregroundStyle(DesignTokens.Palette.primaryText)
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { service.start() }
    }
}

// MARK: Screen — capture-first, strong "Scatta"

struct ScreenFilesWidget: View {
    @EnvironmentObject private var service: ScreenshotService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                // Primary capture — visually dominant.
                Button { service.captureInteractive() } label: {
                    Label(ScreenshotStrings.capture, systemImage: "camera.viewfinder")
                        .font(.system(size: 12, weight: .bold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .frame(maxWidth: .infinity)
                        .background(DesignTokens.Palette.statusRunning.opacity(0.22), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .foregroundStyle(DesignTokens.Palette.statusRunning)
                }
                .buttonStyle(.plain)
                .help(ScreenshotStrings.capture)
                .accessibilityLabel(Text(ScreenshotStrings.captureAccessibility))
                // Secondary record control.
                Button { service.toggleRecording() } label: {
                    ZStack {
                        Circle().strokeBorder(service.isRecording ? DesignTokens.Palette.statusFailure : .white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 26, height: 26)
                        if service.isRecording {
                            RoundedRectangle(cornerRadius: 2).fill(DesignTokens.Palette.statusFailure).frame(width: 9, height: 9)
                        } else {
                            Circle().fill(DesignTokens.Palette.statusFailure.opacity(0.85)).frame(width: 11, height: 11)
                        }
                    }
                }.buttonStyle(.plain).help(service.isRecording ? "Stop recording" : "Record screen")
            }
            if service.isRecording {
                Text("REC \(service.formattedElapsed)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(DesignTokens.Palette.statusFailure)
            }
            if settings.settings.screenShowThumbnails { thumbnails }
            Spacer(minLength: 0)
        }
        .padding(9)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task { service.start() }
    }

    private var thumbnails: some View {
        HStack(spacing: 4) {
            if service.recent.isEmpty {
                Text("No recent screenshots").font(.system(size: 8)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            } else {
                ForEach(service.recent.prefix(3), id: \.self) { url in
                    if let img = NSImage(contentsOf: url) {
                        Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                            .frame(width: 30, height: 20).clipShape(RoundedRectangle(cornerRadius: 3))
                            .onTapGesture { NSWorkspace.shared.open(url) }
                    }
                }
                Button { NSWorkspace.shared.open(service.saveLocation) } label: {
                    Image(systemName: "folder").font(.system(size: 9))
                }.buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
            Spacer(minLength: 0)
        }
    }
}
