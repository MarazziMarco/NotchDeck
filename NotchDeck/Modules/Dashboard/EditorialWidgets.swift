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
    @State private var selection = ShelfSelection()

    private var order: [UUID] { store.items.map(\.id) }

    var body: some View {
        ZStack {
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
        .contentShape(Rectangle())
        .onTapGesture { selection.clear() }        // clicking empty space clears selection
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            // A drop that came FROM the shelf itself is a safe no-op — never a
            // re-import (which previously deleted the file).
            if ShelfDrag.isInternal(providers) { return true }
            for p in providers where p.canLoadObject(ofClass: URL.self) {
                _ = p.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { store.add(urls: [url]) } }
                }
            }
            return true
        }
        .onChange(of: store.items.count) { _, _ in selection.prune(validIDs: Set(order)) }
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 30, weight: .light))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
                Text("Drop files").font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.tertiaryText)
            }
        } else {
            VStack(spacing: 2) {
                if selection.count > 1 {
                    Text("\(selection.count) selected").font(.system(size: 9))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).padding(.top, 4)
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: FileShelfGrid.cellMinWidth,
                                                           maximum: FileShelfGrid.cellMaxWidth),
                                                 spacing: 12, alignment: .top)],
                              alignment: .leading, spacing: 12) {
                        ForEach(store.items) { item in
                            FileShelfGridCell(item: item, selection: $selection, order: order)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }
}

/// One compact File Shelf cell: icon/thumbnail + two-line centred filename with
/// native-style multi-selection and group drag-out. Fixed footprint.
struct FileShelfGridCell: View {
    let item: FileShelfItem
    @Binding var selection: ShelfSelection
    let order: [UUID]
    @EnvironmentObject private var store: FileShelfStore
    @State private var hovering = false

    private var isSelected: Bool { selection.contains(item.id) }
    /// The group to drag/act on: the whole selection if this item is selected,
    /// otherwise just this item.
    private var groupIDs: [UUID] {
        isSelected ? order.filter { selection.contains($0) } : [item.id]
    }

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: item.icon).resizable().aspectRatio(contentMode: .fit)
                .frame(width: FileShelfGrid.iconSize, height: FileShelfGrid.iconSize)
                .opacity(item.isMissing ? 0.4 : 1)
                .overlay { if item.resolveURL() != nil { groupDragOverlay } }
            Text(item.name).font(.system(size: 9.5)).lineLimit(2)
                .multilineTextAlignment(.center).truncationMode(.middle)
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .frame(width: FileShelfGrid.cellMinWidth - 6, height: FileShelfGrid.cellHeight)
        .padding(4)
        .background(cellBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(isSelected ? DesignTokens.Palette.statusRunning : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { handleClick() }
        .help(item.path)
        .accessibilityLabel(accessibilityLabel)
        .contextMenu { contextMenu }
    }

    private var cellBackground: Color {
        if isSelected { return DesignTokens.Palette.statusRunning.opacity(0.16) }
        return hovering ? DesignTokens.Palette.cardFillHover : .clear
    }

    /// Group-aware drag: carries all selected URLs (or just this one).
    private var groupDragOverlay: some View {
        let ids = groupIDs
        let urls = store.urls(for: ids)
        return FileDragSource(urls: urls, icon: item.icon, identifiers: ids.map(\.uuidString)) { op in
            store.completeGroupDrag(items: ids, operation: op)
        }
    }

    private func handleClick() {
        let mods = NSEvent.modifierFlags
        if mods.contains(.command) { selection.toggle(item.id) }
        else if mods.contains(.shift) { selection.range(to: item.id, order: order) }
        else { selection.click(item.id) }
    }

    private var accessibilityLabel: Text {
        let pos = (order.firstIndex(of: item.id) ?? 0) + 1
        let state = isSelected ? "selected, \(pos) of \(order.count)" : "\(pos) of \(order.count)"
        return Text("\(item.name), \(state)")
    }

    @ViewBuilder private var contextMenu: some View {
        // Right-clicking an unselected item targets only it.
        let ids = isSelected && selection.count > 1 ? groupIDs : [item.id]
        let n = ids.count
        let suffix = n > 1 ? "\(n) Items" : "Item"
        Button(n > 1 ? "Open \(suffix)" : "Open") {
            for u in store.urls(for: ids) { NSWorkspace.shared.open(u) }
        }
        Button("Reveal \(n > 1 ? "\(n) Items " : "")in Finder") {
            NSWorkspace.shared.activateFileViewerSelecting(store.urls(for: ids))
        }
        Button("Quick Look") { if let u = item.resolveURL() { QuickLookPreview.shared.preview(url: u) } }
        Divider()
        if item.intakeMode == .keepOriginalReference {
            Button("Remove \(n > 1 ? "\(n) Items " : "")from Shelf", role: .destructive) {
                store.removeReferences(ids)
            }
        } else {
            Button("Move \(n > 1 ? "\(n) Items " : "")to Trash", role: .destructive) {
                store.moveSelectionToTrash(ids)
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
