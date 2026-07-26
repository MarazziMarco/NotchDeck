import SwiftUI

/// Pure layout constants for the Home Now Playing widget, so the vertical
/// composition is deterministic and unit-testable.
enum NowPlayingComposition {
    /// Artwork edge as a fraction of the zone height (raised from 0.60).
    static let artworkHeightRatio: CGFloat = 0.66
    /// Bottom padding used to raise the group's visual centre above the middle.
    static let bottomRaise: CGFloat = 12

    static func artworkSide(zone: CGSize) -> CGFloat {
        min(zone.width, zone.height * artworkHeightRatio)
    }
    /// Signed offset of the group centre from the zone centre. Negative = raised
    /// (centre-aligned group nudged up by half the bottom padding).
    static func centerOffsetFromMiddle() -> CGFloat { -bottomRaise / 2 }
}

// MARK: Quick Note — near-square post-it, full paper

struct EditorialNote: View {
    @EnvironmentObject private var service: QuickNoteService
    @EnvironmentObject private var settings: SettingsStore

    private var color: NoteColor { settings.settings.noteColor }
    private var paper: PaperStyleIntensity { settings.settings.paperStyleIntensity }

    var body: some View {
        GeometryReader { geo in
            // Keep the post-it near-square: width follows height (aspect ~1.05),
            // centred in the zone with intentional negative space if the zone is
            // wider — never stretched into a banner.
            let side = min(geo.size.width, geo.size.height * 1.05)
            sheet
                .frame(width: side, height: geo.size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var sheet: some View {
        ZStack(alignment: .topLeading) {
            // Full paper surface — the whole area is the note.
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [color.paper, color.paper.opacity(0.9)],
                                     startPoint: .top, endPoint: .bottom))
            if paper.showsFold {
                Path { p in p.move(to: .zero); p.addLine(to: CGPoint(x: 16, y: 0)); p.addLine(to: CGPoint(x: 0, y: 16)) }
                    .fill(color.ink.opacity(0.10)).frame(width: 16, height: 16)
            }
            // Editable text fills most of the sheet.
            TextEditor(text: $service.text)
                .font(.system(size: settings.settings.noteFontSize.points, weight: .medium))
                .scrollContentBackground(.hidden)
                .foregroundStyle(color.ink)
                .tint(color.ink)
                .padding(10)
                .overlay(alignment: .topLeading) {
                    if service.isEmpty {
                        Text("Jot a note…").font(.system(size: settings.settings.noteFontSize.points, weight: .medium))
                            .foregroundStyle(color.ink.opacity(0.4)).padding(14).allowsHitTesting(false)
                    }
                }
            if settings.settings.noteShowTitle {
                Image(systemName: "pencil.and.scribble").font(.system(size: 10))
                    .foregroundStyle(color.ink.opacity(0.5))
                    .padding(6).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .shadow(color: .black.opacity(0.4), radius: paper.shadow + 2, y: paper.shadow / 2 + 1)
    }
}

// MARK: Now Playing — vertical, large artwork on top, controls below

struct EditorialNowPlaying: View {
    @EnvironmentObject private var service: NowPlayingService

    var body: some View {
        GeometryReader { geo in
            // Slightly larger artwork; the whole group is centred in the zone and
            // then raised a little (bottom padding) so it never feels bottom-heavy
            // or compressed — controls stay grouped beneath the artwork.
            let artH = NowPlayingComposition.artworkSide(zone: geo.size)
            VStack(spacing: 7) {
                artwork.frame(width: artH, height: artH)
                VStack(spacing: 1) {
                    Text(service.track?.title ?? "Nothing playing")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.Palette.primaryText)
                    Text(service.track?.artist ?? (service.providerAvailable ? " " : "Press play to start Music"))
                        .font(.system(size: 10)).lineLimit(1)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
                transport
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(.bottom, NowPlayingComposition.bottomRaise)   // raises the visual centre
        }
        .task { service.start() }
    }

    private var artwork: some View {
        ZStack {
            if let url = service.artworkURL {
                AsyncImage(url: url) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: { fallback }
            } else {
                fallback
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.35), radius: 5, y: 3)
    }

    /// Polished large fallback (a disc) — never a small grey square.
    private var fallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.12), Color(white: 0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(Color(white: 0.09)).padding(14)
            Circle().strokeBorder(.white.opacity(0.06), lineWidth: 8).padding(14)
            Circle().fill(Color(white: 0.03)).frame(width: 12, height: 12)
            Image(systemName: "music.note").font(.system(size: 20))
                .foregroundStyle(DesignTokens.Palette.secondaryText).opacity(0.7)
                .offset(y: -2)
            if service.track?.isPlaying == true {
                Equalizer().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).padding(6)
            }
        }
    }

    private var transport: some View {
        HStack(spacing: 16) {
            tb("backward.fill", 12) { service.previous() }
            tb(service.track?.isPlaying == true ? "pause.circle.fill" : "play.circle.fill", 20) { service.playPause() }
            tb("forward.fill", 12) { service.next() }
        }
    }
    private func tb(_ icon: String, _ size: CGFloat, _ action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: size)) }
            .buttonStyle(.plain).foregroundStyle(DesignTokens.Palette.primaryText)
    }
}

// MARK: File Shelf — full-height vertical tray

struct EditorialFileShelf: View {
    @EnvironmentObject private var store: FileShelfStore
    @State private var targeted = false

    var body: some View {
        ZStack {
            // Recessed tray with a bottom lip + inward shadow.
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.4))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(targeted ? DesignTokens.Palette.statusRunning.opacity(0.7) : .white.opacity(0.07),
                                      lineWidth: targeted ? 1.5 : 1))
                .shadow(color: .black.opacity(0.5), radius: 3, y: 2)
            if targeted {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.Palette.statusRunning.opacity(0.10))
            }
            content
        }
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for p in providers where p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { store.add(urls: [url]) } }
                }
            }
            return true
        }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty {
            // Empty state fills the module and stays centred (the whole tray is the
            // drop target).
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 30, weight: .light))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Text("Drop files").font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
        } else {
            // Populated: compact top-leading adaptive icon grid — each file is ONE
            // compact cell, cells fill horizontally then wrap. Never a full-width
            // row. Unused space stays outside the cells.
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: FileShelfGrid.cellMinWidth,
                                                       maximum: FileShelfGrid.cellMaxWidth),
                                             spacing: 12, alignment: .top)],
                          alignment: .leading, spacing: 12) {
                    ForEach(store.items) { item in FileShelfGridCell(item: item) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// One compact File Shelf cell: icon/thumbnail + two-line centred filename. Fixed
/// footprint — never expands to the module width/height.
struct FileShelfGridCell: View {
    let item: FileShelfItem
    @EnvironmentObject private var store: FileShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon).resizable().aspectRatio(contentMode: .fit)
                .frame(width: FileShelfGrid.iconSize, height: FileShelfGrid.iconSize)
                .opacity(item.isMissing ? 0.4 : 1)
                .modifier(DragOutModifier(item: item))
            Text(item.name).font(.system(size: 9.5)).lineLimit(2)
                .multilineTextAlignment(.center).truncationMode(.middle)
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .frame(width: FileShelfGrid.cellMinWidth - 6, height: FileShelfGrid.cellHeight)
        .padding(4)
        .background(hovering ? DesignTokens.Palette.cardFillHover : .clear,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onHover { hovering = $0 }
        .help(item.path)
        .contextMenu {
            Button("Open") { if let u = item.resolveURL() { NSWorkspace.shared.open(u) } }
            Button("Reveal in Finder") { if let u = item.resolveURL() { NSWorkspace.shared.activateFileViewerSelecting([u]) } }
            Button("Quick Look") { if let u = item.resolveURL() { QuickLookPreview.shared.preview(url: u) } }
            Divider()
            if item.intakeMode == .keepOriginalReference {
                Button("Remove from Shelf", role: .destructive) { store.remove(item) }
            } else {
                Button("Move to Trash", role: .destructive) { store.moveToTrash(item) }
            }
        }
    }
}

// MARK: Mirror — large circle, no backing card

struct EditorialMirror: View {
    @EnvironmentObject private var service: MirrorService
    @EnvironmentObject private var settings: SettingsStore
    @State private var hovering = false

    var body: some View {
        // The circle stays fixed. The zoom affordance is an OVERLAY (opacity only)
        // so hover never changes layout height and the circle never shifts.
        circle
            .overlay(alignment: .bottom) {
                zoomAffordance
                    .padding(.bottom, 2)
                    .opacity(hovering ? 1 : 0)
                    .allowsHitTesting(hovering)
                    .animation(.easeOut(duration: 0.15), value: hovering)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onHover { hovering = $0 }
            .task { await service.activateIfEnabled() }
            .onDisappear { service.deactivateForHidden() }
    }

    private var circle: some View {
        ZStack {
            if case .running = service.state {
                CameraPreviewView(session: service.session,
                                  mirrored: settings.settings.mirrorOrientation.isMirrored)
                    .scaleEffect(settings.settings.mirrorCircular ? settings.settings.mirrorCropLevel.scale : 1)
                    .clipShape(Circle())
            } else {
                Circle().fill(Color.white.opacity(0.05))
                    .overlay(Image(systemName: service.state == .denied ? "video.slash" : "web.camera")
                        .font(.system(size: 22)).foregroundStyle(DesignTokens.Palette.tertiaryText))
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.14), lineWidth: 1))
        .overlay(alignment: .topLeading) {
            Circle().fill(.white.opacity(0.06)).frame(width: 12, height: 12).blur(radius: 3).offset(x: 10, y: 10)
        }
        .overlay(alignment: .bottomTrailing) {
            if service.isEnabled {
                Circle().fill(DesignTokens.Palette.statusSuccess).frame(width: 7, height: 7).padding(4)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Circle())
        .onTapGesture { service.toggle() }
        .help(service.isEnabled ? "Turn Mirror off" : "Turn Mirror on")
    }

    private var zoomAffordance: some View {
        Menu {
            ForEach(MirrorCropLevel.allCases) { level in
                Button(level.label) { settings.settings.mirrorCropLevel = level }
            }
        } label: {
            Image(systemName: "plus.magnifyingglass").font(.system(size: 9)).padding(4)
                .background(.black.opacity(0.5), in: Capsule())
                .foregroundStyle(DesignTokens.Palette.secondaryText)
        }.menuStyle(.borderlessButton).fixedSize()
    }
}
