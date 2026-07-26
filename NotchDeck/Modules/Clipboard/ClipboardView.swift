import SwiftUI

/// Expanded Clipboard history UI: search, pinned + recent items, per-item actions.
struct ClipboardExpandedView: View {
    @EnvironmentObject private var service: ClipboardService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 8) {
            header
            searchField
            if service.filteredItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: ClipboardRow.spacing) {
                        ForEach(service.filteredItems) { item in
                            ClipboardRow(item: item,
                                         onCopy: { service.restore(item) },
                                         onPin: { service.togglePin(item) },
                                         onDelete: { service.remove(item) })
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .padding(DesignTokens.Metrics.contentPadding)
    }

    private var header: some View {
        HStack {
            Label("Clipboard", systemImage: "doc.on.clipboard")
                .font(.headline)
                .foregroundStyle(DesignTokens.Palette.primaryText)
            Spacer()
            Toggle(isOn: Binding(
                get: { settings.settings.clipboardMonitoringPaused },
                set: { settings.settings.clipboardMonitoringPaused = $0; service.isPaused = $0 }
            )) { Text("Pause").font(.caption) }
                .toggleStyle(.switch)
                .controlSize(.mini)
            Menu {
                Button("Clear history", role: .destructive) { service.clearAll() }
                Button("Clear unpinned") { service.clearUnpinned() }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search", text: $service.searchQuery)
                .textFieldStyle(.plain)
        }
        .padding(6)
        .background(DesignTokens.Palette.hairline, in: RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "doc.on.clipboard")
                .font(.largeTitle).foregroundStyle(.tertiary)
            Text(service.searchQuery.isEmpty ? "Nothing copied yet" : "No matches")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
    }
}

/// A single clipboard row with an appropriate preview and hover actions.
struct ClipboardRow: View {
    static let spacing: CGFloat = 4
    let item: ClipboardItem
    let onCopy: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            icon
            VStack(alignment: .leading, spacing: 2) {
                Text(item.preview)
                    .lineLimit(2)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                if let src = item.sourceAppName {
                    Text(src).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 4)
            if hovering || item.pinned {
                Button(action: onPin) {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                }.buttonStyle(.borderless).help("Pin")
            }
            if hovering {
                Button(action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless).help("Delete")
            }
        }
        .padding(8)
        .background(hovering ? DesignTokens.Palette.hairline : Color.clear,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius))
        .contentShape(Rectangle())
        .onTapGesture(perform: onCopy)
        .onHover { hovering = $0 }
    }

    @ViewBuilder private var icon: some View {
        if item.kind == .image, let data = item.imageData, let img = NSImage(data: data) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 32, height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: symbol).frame(width: 32, height: 32)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
        }
    }

    private var symbol: String {
        switch item.kind {
        case .text: return "text.alignleft"
        case .richText: return "textformat"
        case .image: return "photo"
        case .url: return "link"
        case .fileURL: return "doc"
        }
    }
}
