import SwiftUI
import QuickLookUI
import UniformTypeIdentifiers

/// Expanded File Shelf: a drop target plus a grid of parked files that can be
/// dragged back out to Finder using native pasteboard mechanisms.
struct FileShelfExpandedView: View {
    @EnvironmentObject private var store: FileShelfStore
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("File Shelf", systemImage: "tray.full")
                    .font(.headline).foregroundStyle(DesignTokens.Palette.primaryText)
                Spacer()
                if !store.items.isEmpty {
                    Button("Clear") { store.clear() }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            if store.needsMoveExplainer && !settings.settings.fileShelfMoveExplained {
                moveExplainer
            }
            if let err = store.lastError {
                Text(err).font(.caption2).foregroundStyle(DesignTokens.Palette.statusFailure)
                    .lineLimit(2).onTapGesture { store.lastError = nil }
            }
            content
        }
        .padding(DesignTokens.Metrics.contentPadding)
    }

    /// One-time explainer for move-into-shelf intake.
    private var moveExplainer: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill").foregroundStyle(DesignTokens.Palette.statusRunning)
            VStack(alignment: .leading, spacing: 4) {
                Text("Files dropped here are moved from their current folder and safely stored in NotchDeck until you place them somewhere else.")
                    .font(.caption)
                Button("Don't show again") {
                    settings.settings.fileShelfMoveExplained = true
                    store.dismissMoveExplainer()
                }
                .buttonStyle(.borderless).controlSize(.small)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(DesignTokens.Palette.hairline, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var content: some View {
        if store.items.isEmpty {
            dropZone
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: FileShelfGrid.cellMinWidth,
                                                        maximum: FileShelfGrid.cellMaxWidth),
                                             spacing: 10)], spacing: 12) {
                    ForEach(store.items) { item in
                        FileShelfTile(item: item, onRemove: { store.remove(item) })
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 150)
        }
    }

    /// Empty state: the drop icon is the visual focus; "Drop files" is small and
    /// secondary. The whole card is the drop target (handled by the parent).
    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [7]))
            .foregroundStyle(DesignTokens.Palette.hairline)
            .frame(maxWidth: .infinity, minHeight: 150)
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                    Text("Drop files")
                        .font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                }
            }
    }
}

/// Grid sizing for the File Shelf (icon-grid look, not a list).
enum FileShelfGrid {
    static let iconSize: CGFloat = 52
    static let cellMinWidth: CGFloat = 88
    static let cellMaxWidth: CGFloat = 112
    static let cellHeight: CGFloat = 108
    static let spacing: CGFloat = 12
    /// Columns that fit in a given content width (adaptive minimum + spacing).
    static func columns(forWidth width: CGFloat) -> Int {
        max(1, Int((width + spacing) / (cellMinWidth + spacing)))
    }
}

/// A single shelved file: icon, name, size, drag-out, context actions.
struct FileShelfTile: View {
    let item: FileShelfItem
    let onRemove: () -> Void
    @EnvironmentObject private var store: FileShelfStore
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: item.icon)
                .resizable().aspectRatio(contentMode: .fit)
                .frame(width: FileShelfGrid.iconSize, height: FileShelfGrid.iconSize)
                .opacity(item.isMissing ? 0.4 : 1)
                .modifier(DragOutModifier(item: item))
            Text(item.name).font(.system(size: 10)).lineLimit(2)
                .multilineTextAlignment(.center).truncationMode(.middle)
                .foregroundStyle(DesignTokens.Palette.primaryText)
            Text(item.isMissing ? "Missing" : item.displaySize)
                .font(.system(size: 8.5))
                .foregroundStyle(item.isMissing ? DesignTokens.Palette.statusFailure
                                                 : DesignTokens.Palette.tertiaryText)
        }
        .frame(width: FileShelfGrid.cellMinWidth - 8, height: FileShelfGrid.cellHeight)
        .padding(4)
        .background(hovering ? DesignTokens.Palette.hairline : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .onHover { hovering = $0 }
        .help(item.path)
        .contextMenu { menu }
    }

    @ViewBuilder private var menu: some View {
        Button("Open") { open() }
        Button("Show in Finder") { revealInFinder() }
        Button("Quick Look") { quickLook() }
        Divider()
        if item.intakeMode == .moveIntoShelf {
            // Staged item: never offer an ambiguous destructive delete.
            Button("Restore to original location") { restore() }
            Button("Move to…") { moveTo() }
            Button("Move to Trash", role: .destructive) { store.moveToTrash(item) }
        } else {
            Button("Remove from Shelf", role: .destructive, action: onRemove)
        }
    }

    private func open() {
        guard let url = item.resolveURL() else { return }
        NSWorkspace.shared.open(url)
    }
    private func revealInFinder() {
        guard let url = item.resolveURL() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    private func quickLook() {
        guard let url = item.resolveURL() else { return }
        QuickLookPreview.shared.preview(url: url)
    }
    private func restore() {
        // If the original folder no longer exists, ask for a new destination.
        if item.originalLocationExists {
            store.restore(item)
        } else if let dir = chooseDirectory(prompt: "Restore to…") {
            store.restore(item, to: dir.appendingPathComponent(item.name))
        }
    }
    private func moveTo() {
        if let dir = chooseDirectory(prompt: "Move to…") { store.moveTo(item, directory: dir) }
    }
    private func chooseDirectory(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// Compact File Shelf card for the Utilities side column: count + recent icons
/// + drop hint. Also accepts drops itself.
struct FileShelfCompactCard: View {
    @EnvironmentObject private var store: FileShelfStore
    @State private var targeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "File Shelf", accessory: store.items.isEmpty ? nil : "\(store.items.count)")
            if store.items.isEmpty {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4]))
                    .foregroundStyle(DesignTokens.Palette.hairline)
                    .frame(height: 52)
                    .overlay {
                        Label("Drop files", systemImage: "arrow.down.doc")
                            .font(.caption2).foregroundStyle(DesignTokens.Palette.tertiaryText)
                    }
            } else {
                HStack(spacing: 6) {
                    ForEach(store.items.prefix(4)) { item in
                        Image(nsImage: item.icon).resizable().aspectRatio(contentMode: .fit)
                            .frame(width: 28, height: 28)
                            .opacity(item.isMissing ? 0.4 : 1)
                            .modifier(DragOutModifier(item: item))
                    }
                    if store.items.count > 4 {
                        Text("+\(store.items.count - 4)").font(.caption2)
                            .foregroundStyle(DesignTokens.Palette.secondaryText)
                    }
                    Spacer(minLength: 0)
                }
                .frame(height: 52)
            }
        }
        .dashboardCard()
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(DesignTokens.Palette.statusRunning, lineWidth: targeted ? 1.5 : 0)
        )
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            if ShelfDrag.isInternal(providers) { return true }   // internal drop → no-op
            for provider in providers where provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { store.add(urls: [url]) } }
                }
            }
            return true
        }
    }
}

/// Attaches a real AppKit dragging session so items can be dropped into
/// Finder/apps, and reports the genuine drag result back to the store so the
/// shelf entry is cleared only on a confirmed transfer.
struct DragOutModifier: ViewModifier {
    let item: FileShelfItem
    @EnvironmentObject private var store: FileShelfStore
    func body(content: Content) -> some View {
        if let url = item.resolveURL() {
            content.overlay(
                FileDragSource(url: url, icon: item.icon, identifier: item.id.uuidString) { operation in
                    store.completeDrag(item: item, operation: operation)
                }
            )
        } else {
            content
        }
    }
}
