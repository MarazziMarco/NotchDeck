import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct SharedShelfCard: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedShelf>
    @ObservedObject private var controller: SharedShelfController
    let isEditing: Bool
    @State private var flipped = false
    @State private var draft = ShelfPreferences()
    @State private var targeted = false
    @State private var actionError: String?
    init(library: SharedWidgetLibrary, isEditing: Bool, initiallyFlipped: Bool = false) {
        channel = library.shelf; controller = library.shelfController; self.isEditing = isEditing
        _flipped = State(initialValue: initiallyFlipped); _draft = State(initialValue: library.shelf.value.preferences)
    }
    var body: some View {
        ReversibleWidgetCard(kind: .shelf, accent: .cyan, flipped: $flipped, isEditing: isEditing,
                             onEdit: { draft = channel.value.preferences; flipped = true },
                             onSave: { try channel.update { $0.preferences = draft } }) {
            VStack(spacing: 8) {
                HStack {
                    Text("\(channel.value.items.count) elementi").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    if controller.isAdding { ProgressView().controlSize(.small) }
                    Button { controller.chooseFiles() } label: { Image(systemName: "plus").frame(width: 26, height: 24) }
                        .buttonStyle(.plain).help("Aggiungi file o cartelle").accessibilityLabel("Aggiungi file o cartelle")
                }
                if channel.value.items.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "tray.and.arrow.down").font(.system(size: 31, weight: .light)).foregroundStyle(.cyan)
                        Text("Trascina qui file e cartelle").font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center)
                        Text("Li ritrovi anche nel notch").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView(.vertical) {
                        VStack(spacing: 6) {
                            ForEach(sortedItems) { item in row(item) }
                        }
                    }.scrollIndicators(.hidden)
                }
                WidgetActionError(message: actionError ?? controller.errorMessage ?? channel.errorMessage)
            }
            .padding(7)
            .background(targeted ? .cyan.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(.cyan.opacity(targeted ? 0.7 : 0.14), style: StrokeStyle(lineWidth: 1, dash: [5, 4])) }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $targeted, perform: receive)
        } settings: {
            Text("Quando aggiungi un file").fontWeight(.medium)
            Picker("Modalità", selection: $draft.copyIntoShelf) {
                Text("Collega").tag(false); Text("Copia").tag(true)
            }.pickerStyle(.segmented).labelsHidden()
            Text(draft.copyIntoShelf ? "Conserva una copia persistente nello scaffale. L’originale rimane al suo posto."
                                    : "Mantiene un collegamento al file originale, che rimane al suo posto.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6)).fixedSize(horizontal: false, vertical: true)
            Toggle("Più recenti prima", isOn: $draft.newestFirst)
            Toggle("Mostra dimensione file", isOn: $draft.showFileSize)
        }
        .font(.system(size: 12))
    }
    private var sortedItems: [SharedShelfItem] {
        channel.value.preferences.newestFirst ? channel.value.items.sorted { $0.addedAt > $1.addedAt }
                                             : channel.value.items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private func row(_ item: SharedShelfItem) -> some View {
        let url = item.resolveURL()
        return HStack(spacing: 8) {
            Button {
                if let url { NSWorkspace.shared.open(url) }
            } label: {
                HStack(spacing: 8) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url?.path ?? item.originalPath)).resizable().scaledToFit().frame(width: 27, height: 27)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        if url == nil { Text("File non disponibile").font(.system(size: 9)).foregroundStyle(.orange) }
                        else if channel.value.preferences.showFileSize {
                            Text(ByteCountFormatter.string(fromByteCount: item.byteSize, countStyle: .file)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(url == nil)
            Menu {
                Button("Mostra nel Finder") { if let url { NSWorkspace.shared.activateFileViewerSelecting([url]) } }.disabled(url == nil)
                Button(item.isReference ? "Rimuovi collegamento" : "Sposta nel Cestino", role: .destructive) {
                    do { try controller.remove(item.id); actionError = nil } catch { actionError = error.localizedDescription }
                }
            } label: { Image(systemName: "ellipsis").frame(width: 20, height: 22) }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("Azioni per \(item.name)")
        }
        .padding(7).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .onDrag { url.flatMap { NSItemProvider(contentsOf: $0) } ?? NSItemProvider() }
        .help(url?.path ?? item.originalPath)
    }
    private func receive(_ providers: [NSItemProvider]) -> Bool {
        guard !isEditing else { return false }
        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                let url: URL? = await withCheckedContinuation { continuation in
                    provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                        if let url = item as? URL { continuation.resume(returning: url) }
                        else if let data = item as? Data { continuation.resume(returning: URL(dataRepresentation: data, relativeTo: nil)) }
                        else if let text = item as? String { continuation.resume(returning: URL(string: text)) }
                        else { continuation.resume(returning: nil) }
                    }
                }
                if let url, url.isFileURL { urls.append(url) }
            }
            await controller.add(urls)
        }
        return !providers.isEmpty
    }
}

struct SharedMusicCard: View {
    @ObservedObject private var channel: SharedWidgetChannel<SharedMusic>
    private let controller: SharedMusicController
    let isEditing: Bool
    @State private var flipped = false
    @State private var draft = MusicPreferences()
    @State private var client = UUID()
    @State private var actionError: String?
    init(library: SharedWidgetLibrary, isEditing: Bool, initiallyFlipped: Bool = false) { channel = library.music; controller = library.musicController; self.isEditing = isEditing; _flipped = State(initialValue: initiallyFlipped); _draft = State(initialValue: library.music.value.preferences) }
    var body: some View {
        ReversibleWidgetCard(kind: .music, accent: .pink, flipped: $flipped, isEditing: isEditing,
                             onEdit: { draft = channel.value.preferences; flipped = true }, onSave: save) {
            VStack(spacing: 12) {
                if channel.value.preferences.enabled {
                    if let track = channel.value.track {
                        HStack(spacing: 12) {
                            if channel.value.preferences.showArtwork { artwork(track).frame(width: 72, height: 72) }
                            VStack(alignment: .leading, spacing: 5) {
                                Text(track.title).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(2)
                                Text(track.artist).font(.system(size: 12)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                                Text(track.app).font(.system(size: 9, weight: .semibold)).foregroundStyle(.pink.opacity(0.8))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer(minLength: 0)
                        if track.duration > 0 {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                ProgressView(value: track.progress(at: context.date)).tint(.pink)
                            }
                        }
                    } else {
                        Spacer(minLength: 0)
                        Image(systemName: "music.note.list").font(.system(size: 34, weight: .light)).foregroundStyle(.pink)
                        Text(channel.value.providerAvailable ? "Scegli un brano nel lettore" : "Apri Music o Spotify")
                            .font(.system(size: 13, weight: .medium)).multilineTextAlignment(.center)
                        if !channel.value.providerAvailable { Button("Apri lettore", action: openPlayer).buttonStyle(.borderless) }
                        Spacer(minLength: 0)
                    }
                    HStack(spacing: 28) {
                        transport("backward.fill", action: .previous, label: "Brano precedente")
                        transport(channel.value.track?.isPlaying == true ? "pause.circle.fill" : "play.circle.fill", action: .playPause, label: "Riproduci o pausa", large: true)
                        transport("forward.fill", action: .next, label: "Brano successivo")
                    }.frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                    Image(systemName: "music.note").font(.system(size: 40, weight: .light)).foregroundStyle(.pink)
                    Text("La tua musica, qui").font(.system(size: 17, weight: .semibold, design: .rounded))
                    Text("Music e Spotify · controlli condivisi").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    Button("Collega lettore") { perform { try controller.connect() } }.buttonStyle(.borderedProminent).tint(.pink.opacity(0.75))
                    Spacer(minLength: 0)
                }
                WidgetActionError(message: actionError ?? channel.value.errorMessage ?? channel.errorMessage)
            }
        } settings: {
            Toggle("Collegamento attivo", isOn: $draft.enabled)
            Picker("Lettore", selection: $draft.player) {
                Text("Automatico").tag("auto"); Text("Music").tag("music"); Text("Spotify").tag("spotify")
            }
            Toggle("Mostra copertina", isOn: $draft.showArtwork)
            Text("Il lettore rimane lo stesso in entrambe le app. macOS può chiedere il permesso di Automazione al primo collegamento.")
                .font(.system(size: 10)).foregroundStyle(.white.opacity(0.6))
        }
        .font(.system(size: 12))
        .onAppear { controller.start(client: client) }
        .onDisappear { controller.stop(client: client) }
    }
    private func save() throws {
        try channel.update {
            $0.preferences = draft
            if !draft.enabled { $0.track = nil; $0.commands = []; $0.leaseOwner = nil; $0.leaseExpiresAt = nil }
        }
        if draft.enabled { controller.poll() }
    }
    private func artwork(_ track: MusicTrack) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13).fill(.pink.opacity(0.15))
            Image(systemName: "music.note").font(.system(size: 30, weight: .light)).foregroundStyle(.pink)
            if let value = track.artworkURL, value.hasPrefix("https://"), let url = URL(string: value) {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }.clipShape(RoundedRectangle(cornerRadius: 13))
    }
    private func transport(_ symbol: String, action: MusicAction, label: String, large: Bool = false) -> some View {
        Button { perform { try controller.send(action) } } label: { Image(systemName: symbol).font(.system(size: large ? 37 : 17)) }
            .buttonStyle(.plain).help(label).accessibilityLabel(label)
    }
    private func perform(_ action: () throws -> Void) { do { try action(); actionError = nil } catch { actionError = error.localizedDescription } }
    private func openPlayer() {
        let identifier = channel.value.preferences.player == "spotify" ? "com.spotify.client" : "com.apple.Music"
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) { NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) }
    }
}
