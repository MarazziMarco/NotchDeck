import SwiftUI

/// Single source of truth for the customization draft (order, visibility, size,
/// preset) plus the opening snapshot restored on Cancel.
struct HomeCustomizationDraft: Equatable {
    var preset: HomeLayoutPreset
    var order: [String]?
    var hidden: [String]
    var widths: [String: EditorialZoneWidth]

    /// Migration: fill gaps without discarding known choices or module data.
    static func migrated(preset: HomeLayoutPreset?, order: [String]?,
                         hidden: [String], widths: [String: EditorialZoneWidth]) -> HomeCustomizationDraft {
        let ids = order ?? EditorialHomeLayout.defaultOrder
        var w = widths
        for id in ids where w[id] == nil { w[id] = .standard }   // unknown sizes → Medium
        return HomeCustomizationDraft(preset: preset ?? .balanced, order: order, hidden: hidden, widths: w)
    }
}

/// Pure, shared reordering engine — the SINGLE source of truth used by the
/// visual preview, the settings rows and keyboard actions. No separate
/// preview-only order state exists.
enum HomeReorder {
    /// Move `drag` to occupy `target`'s slot. No-op for equal/unknown ids; never
    /// duplicates.
    static func move(_ ids: [String], drag: String, onto target: String) -> [String] {
        guard drag != target,
              let from = ids.firstIndex(of: drag),
              let to = ids.firstIndex(of: target) else { return ids }
        var out = ids
        let moved = out.remove(at: from)
        out.insert(moved, at: to)
        return out
    }
    /// Shift a module earlier (-1) / later (+1) — keyboard / context menu.
    static func shift(_ ids: [String], id: String, by delta: Int) -> [String] {
        guard let i = ids.firstIndex(of: id) else { return ids }
        let j = max(0, min(ids.count - 1, i + delta))
        guard j != i else { return ids }
        var out = ids
        out.swapAt(i, j)
        return out
    }
}

/// Polished Home customization sheet. Replaces the old inline per-module edit
/// toolbars: the real Home stays intact behind this sheet and updates live.
/// Native drag-to-reorder (no left/right arrow buttons), visibility toggles,
/// size selectors, a density preset and Reset to Default. All choices persist.
struct HomeCustomizationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var registry: ModuleRegistry
    @Environment(\.dismiss) private var dismiss

    /// Opening snapshot of the four customization fields, restored on Cancel.
    @State private var snapshot: HomeCustomizationDraft?
    @State private var hideWarning = false
    /// Module currently being dragged (nil when idle). Cleared on drop/cancel.
    @State private var dragging: String?

    private var order: [String] {
        settings.settings.editorialOrder ?? EditorialHomeLayout.defaultOrder
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.Palette.separator)
            presetRow
            preview
            Divider().overlay(DesignTokens.Palette.separator)
            List {
                ForEach(order, id: \.self) { id in moduleRow(id) }
                    .onMove(perform: move)   // native drag-to-reorder (macOS)
            }
            .listStyle(.plain).scrollContentBackground(.hidden)
            if hideWarning {
                Text("At least one module must stay visible.")
                    .font(.system(size: 10)).foregroundStyle(DesignTokens.Palette.statusAttention)
                    .padding(.bottom, 2)
            }
            Divider().overlay(DesignTokens.Palette.separator)
            footer
        }
        .frame(width: 660, height: 560)
        .background(DesignTokens.Palette.expandedSurface)
        .preferredColorScheme(.dark)
        .onAppear { if snapshot == nil { snapshot = currentDraft() } }
        .onDisappear { dragging = nil }   // clear a drag if the sheet closes mid-drag
    }

    /// A live simplified preview of the real Home row (order / width / visibility).
    /// Cards are draggable to reorder — reordering updates the same draft the
    /// production Home renders from.
    private var preview: some View {
        let visible = order.filter { !settings.settings.editorialHidden.contains($0) }
        return HStack(spacing: max(4, settings.settings.homeLayoutPreset.tokens.moduleGap * 0.4)) {
            ForEach(visible, id: \.self) { id in
                let w = settings.settings.editorialWidths[id] ?? .standard
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(dragging == id ? DesignTokens.Palette.cardFillHover : DesignTokens.Palette.cardFill)
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(
                        dragging == id ? DesignTokens.Palette.statusAttention : DesignTokens.Palette.hairline))
                    .overlay(
                        VStack(spacing: 3) {
                            Image(systemName: "line.3.horizontal").font(.system(size: 8))
                                .foregroundStyle(DesignTokens.Palette.tertiaryText)
                            Image(systemName: registry.module(id: id)?.iconName ?? "square")
                            Text(registry.module(id: id)?.displayName ?? id).font(.system(size: 8)).lineLimit(1)
                        }.foregroundStyle(DesignTokens.Palette.secondaryText))
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .layoutPriority(Double(w.multiplier))
                    .onDrag { dragging = id; return NSItemProvider(object: id as NSString) }
                    .onDrop(of: [.text], isTargeted: nil) { providers in
                        drop(onto: id, providers: providers)
                    }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .animation(.easeInOut(duration: 0.2), value: order)
    }

    /// Reorder the dragged module to the dropped card's slot, via the shared
    /// reorder engine. Invalid/cancelled drops leave the order unchanged.
    private func drop(onto target: String, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { dragging = nil; return false }
        _ = provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let src = obj as? String else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.2)) {
                    settings.settings.editorialOrder = HomeReorder.move(order, drag: src, onto: target)
                }
                dragging = nil
            }
        }
        return true
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Customize Home").font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                Text("Reorder, show or hide, and resize your Home modules.")
                    .font(.system(size: 11)).foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            Spacer()
            Button("Cancel") { cancel() }.keyboardShortcut(.cancelAction)
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private var presetRow: some View {
        HStack(spacing: 8) {
            Text("Layout").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Picker("", selection: Binding(
                get: { settings.settings.homeLayoutPreset },
                set: { settings.settings.homeLayoutPreset = $0 })) {
                ForEach(HomeLayoutPreset.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func moduleRow(_ id: String) -> some View {
        let module = registry.module(id: id)
        let hidden = settings.settings.editorialHidden.contains(id)
        let width = settings.settings.editorialWidths[id] ?? .standard
        let pos = (order.firstIndex(of: id) ?? 0) + 1
        return HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12)).foregroundStyle(DesignTokens.Palette.tertiaryText)
                .accessibilityLabel("Drag handle")
            Image(systemName: module?.iconName ?? "square.dashed")
                .font(.system(size: 16)).frame(width: 26)
                .foregroundStyle(hidden ? .tertiary : .primary)
            VStack(alignment: .leading, spacing: 1) {
                Text(module?.displayName ?? id).font(.system(size: 12.5, weight: .medium))
                Text(descriptionFor(id)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { width },
                set: { settings.settings.editorialWidths[id] = $0 })) {
                ForEach(EditorialZoneWidth.allCases) { Text($0.sizeLabel).tag($0) }
            }
            .labelsHidden().frame(width: 110).disabled(hidden)
            Toggle("", isOn: Binding(
                get: { !hidden },
                set: { show in setVisible(id, show) }))
            .labelsHidden().toggleStyle(.switch)
        }
        .padding(.vertical, 4)
        .opacity(hidden ? 0.55 : 1)
        .contextMenu {
            Button("Move Earlier") { shift(id, by: -1) }
            Button("Move Later") { shift(id, by: 1) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(module?.displayName ?? id), position \(pos) of \(order.count)")
        .accessibilityActions {
            Button("Move Earlier") { shift(id, by: -1) }
            Button("Move Later") { shift(id, by: 1) }
        }
    }

    /// Keyboard / context reorder — same source of truth as drag.
    private func shift(_ id: String, by delta: Int) {
        withAnimation(.easeInOut(duration: 0.18)) {
            settings.settings.editorialOrder = HomeReorder.shift(order, id: id, by: delta)
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Default", role: .destructive) { reset() }
                .buttonStyle(.plain).foregroundStyle(.red).font(.system(size: 11))
            Spacer()
        }
        .padding(16)
    }

    private func move(from source: IndexSet, to dest: Int) {
        var ids = order
        ids.move(fromOffsets: source, toOffset: dest)
        settings.settings.editorialOrder = ids
    }

    /// Toggle visibility, but never allow the last visible module to be hidden.
    private func setVisible(_ id: String, _ show: Bool) {
        if show {
            settings.settings.editorialHidden.removeAll { $0 == id }
            hideWarning = false
        } else {
            let remaining = order.filter { !settings.settings.editorialHidden.contains($0) && $0 != id }
            guard !remaining.isEmpty else { hideWarning = true; return }
            if !settings.settings.editorialHidden.contains(id) {
                settings.settings.editorialHidden.append(id)
            }
        }
    }

    private func reset() {
        settings.settings.editorialOrder = nil
        settings.settings.editorialHidden = []
        settings.settings.editorialWidths = [:]
        settings.settings.homeLayoutPreset = .balanced
    }

    // MARK: Cancel / Done draft

    private func currentDraft() -> HomeCustomizationDraft {
        HomeCustomizationDraft(
            preset: settings.settings.homeLayoutPreset,
            order: settings.settings.editorialOrder,
            hidden: settings.settings.editorialHidden,
            widths: settings.settings.editorialWidths)
    }

    /// Restore the exact configuration captured when the sheet opened.
    private func cancel() {
        if let s = snapshot {
            settings.settings.homeLayoutPreset = s.preset
            settings.settings.editorialOrder = s.order
            settings.settings.editorialHidden = s.hidden
            settings.settings.editorialWidths = s.widths
        }
        dismiss()
    }

    private func descriptionFor(_ id: String) -> String {
        switch id {
        case "quickNote": return "A quick sticky note"
        case "nowPlaying": return "Now playing controls"
        case "fileShelf": return "Temporary file staging"
        case "mirror": return "Live camera mirror"
        default: return "Home module"
        }
    }
}
