import SwiftUI

/// The Utilities → More dashboard: a customizable 2-column grid of More-eligible
/// built-in + community modules. Its "Open Module Library" manages ONLY More — it
/// never touches Home. Placement uses the shared `moduleEnabled` flag; order and
/// size live in the independent `AppSettings.moreLayout`.
struct MoreDashboardView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var community: CommunityModuleRegistry
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showingLibrary = false
    @State private var editing = false
    @State private var dragging: String?

    private let columns = MoreGridSolver.columns
    private let rowUnit: CGFloat = 92
    private let gap: CGFloat = 10

    private var moduleViews: [MoreModuleView] {
        MoreCatalog.views(registry: registry, community: community)
    }
    private var definitions: [MoreModuleDescriptor] { moduleViews.map(\.descriptor) }
    private func isPlaced(_ id: String) -> Bool {
        guard let d = definitions.first(where: { $0.id == id }) else { return false }
        return MoreCatalog.isPlaced(d, settings: settings.settings)
    }
    private var placedIDs: [String] {
        MoreLayoutNormalizer.placedOrder(settings.settings.moreLayout,
                                         definitions: definitions, isEnabled: isPlaced)
    }
    private func view(_ id: String) -> MoreModuleView? { moduleViews.first { $0.id == id } }
    private func size(_ id: String) -> MoreModuleSize {
        MoreLayoutNormalizer.size(id, in: settings.settings.moreLayout, definitions: definitions)
    }

    var body: some View {
        VStack(spacing: 6) {
            toolbar
            if placedIDs.isEmpty { emptyState } else { grid }
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $showingLibrary) {
            MoreModuleLibraryView(moduleViews: moduleViews)
                .frame(width: 460, height: 460)
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 8) {
            Spacer()
            if !placedIDs.isEmpty {
                chip(editing ? "Done" : "Customize") { withMotion { editing.toggle() } }
            }
            chip("Open Module Library") { showingLibrary = true }
                .accessibilityLabel("Open Module Library")
            Menu {
                Button("Restore Default More Layout") { restoreDefault() }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("More options")
        }
        .padding(.horizontal, 12)
    }

    private func chip(_ title: String, _ action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.plain).font(.system(size: 10.5, weight: .medium))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(DesignTokens.Palette.cardFillHover, in: Capsule())
            .foregroundStyle(DesignTokens.Palette.secondaryText)
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2").font(.system(size: 26))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
            Text("No More modules yet").font(.callout)
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            Text("Add built-in and community modules to this dashboard.")
                .font(.caption).foregroundStyle(DesignTokens.Palette.tertiaryText)
            Button("Open Module Library") { showingLibrary = true }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(DesignTokens.Palette.cardFillHover, in: Capsule())
                .foregroundStyle(DesignTokens.Palette.primaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            GeometryReader { geo in
                let cellW = (geo.size.width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                let items = placedIDs.map { MoreGridSolver.Item(id: $0, size: size($0)) }
                let result = MoreGridSolver.solve(items)
                ZStack(alignment: .topLeading) {
                    ForEach(result.cells, id: \.id) { cell in
                        if let mv = view(cell.id) {
                            MoreCardHost(module: mv, size: size(cell.id), editing: editing,
                                         canResize: mv.descriptor.supportedSizes.count > 1,
                                         onResize: { setSize(cell.id, $0) },
                                         onRemove: { remove(cell.id) },
                                         onMoveUp: { move(cell.id, by: -1) },
                                         onMoveDown: { move(cell.id, by: 1) })
                                .frame(width: cellW * CGFloat(cell.w) + gap * CGFloat(cell.w - 1),
                                       height: rowUnit * CGFloat(cell.h) + gap * CGFloat(cell.h - 1))
                                .position(x: originX(cell, cellW) + (cellW * CGFloat(cell.w) + gap * CGFloat(cell.w - 1)) / 2,
                                          y: originY(cell) + (rowUnit * CGFloat(cell.h) + gap * CGFloat(cell.h - 1)) / 2)
                                .opacity(dragging == cell.id ? 0.5 : 1)
                                .modifier(MoreDragReorder(editing: editing, id: cell.id,
                                                          dragging: $dragging, onDrop: { move($0, before: cell.id) }))
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: totalHeight(result), alignment: .topLeading)
            }
            .frame(minHeight: totalHeight(MoreGridSolver.solve(placedIDs.map { MoreGridSolver.Item(id: $0, size: size($0)) })))
            .padding(.horizontal, 12).padding(.bottom, 10)
        }
    }

    private func originX(_ cell: GridCell, _ cellW: CGFloat) -> CGFloat {
        CGFloat(cell.col) * (cellW + gap)
    }
    private func originY(_ cell: GridCell) -> CGFloat { CGFloat(cell.row) * (rowUnit + gap) }
    private func totalHeight(_ result: GridSolver.Result) -> CGFloat {
        let rows = (result.cells.map { $0.row + $0.h }.max() ?? 0)
        return CGFloat(rows) * rowUnit + CGFloat(max(0, rows - 1)) * gap
    }

    // MARK: Mutations (all via the atomic, normalized More store)

    private func setSize(_ id: String, _ s: MoreModuleSize) {
        settings.updateMoreLayout(definitions: definitions) { $0.moreLayout.sizes[id] = s }
    }
    private func remove(_ id: String) {
        settings.updateMoreLayout(definitions: definitions) { $0.moduleEnabled[id] = false }
    }
    private func move(_ id: String, by delta: Int) {
        settings.updateMoreLayout(definitions: definitions) {
            var order = $0.moreLayout.order ?? []
            guard let i = order.firstIndex(of: id) else { return }
            let j = max(0, min(order.count - 1, i + delta))
            order.swapAt(i, j); $0.moreLayout.order = order
        }
    }
    private func move(_ dragID: String, before targetID: String) {
        guard dragID != targetID else { return }
        settings.updateMoreLayout(definitions: definitions) {
            var order = $0.moreLayout.order ?? []
            guard let from = order.firstIndex(of: dragID), let to = order.firstIndex(of: targetID) else { return }
            let moved = order.remove(at: from)
            order.insert(moved, at: order.firstIndex(of: targetID) ?? to)
            $0.moreLayout.order = order
        }
    }
    private func restoreDefault() {
        let defs = definitions
        settings.updateMoreLayout(definitions: defs) {
            $0.moreLayout.order = MoreLayoutNormalizer.defaultOrder(defs)
            $0.moreLayout.sizes = [:]
            for d in defs { $0.moduleEnabled[d.id] = true }   // default = all eligible placed
        }
    }

    private func withMotion(_ change: () -> Void) {
        if reduceMotion { change() } else { withAnimation(.easeInOut(duration: 0.18)) { change() } }
    }
}

/// Drag-to-reorder while editing; a no-op otherwise so normal card controls work.
private struct MoreDragReorder: ViewModifier {
    let editing: Bool
    let id: String
    @Binding var dragging: String?
    let onDrop: (String) -> Void
    func body(content: Content) -> some View {
        if editing {
            content
                .onDrag { dragging = id; return NSItemProvider(object: id as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    _ = providers.first?.loadObject(ofClass: NSString.self) { obj, _ in
                        if let dragged = obj as? String {
                            DispatchQueue.main.async { onDrop(dragged); dragging = nil }
                        }
                    }
                    return true
                }
        } else {
            content
        }
    }
}

/// One More card + (while editing) size / remove / move controls.
struct MoreCardHost: View {
    let module: MoreModuleView
    let size: MoreModuleSize
    let editing: Bool
    let canResize: Bool
    let onResize: (MoreModuleSize) -> Void
    let onRemove: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        module.card(size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .background(DesignTokens.Palette.cardFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(editing ? DesignTokens.Palette.statusRunning.opacity(0.5) : DesignTokens.Palette.hairline,
                              lineWidth: editing ? 1 : 0.6))
            .overlay(alignment: .topTrailing) { if editing { editChrome } }
            .allowsHitTesting(!editing)   // editing disables normal controls (drag/resize instead)
            .accessibilityElement(children: editing ? .ignore : .contain)
            .accessibilityLabel(Text("\(module.descriptor.name), \(module.descriptor.source.label) module, \(size.label)"))
            .accessibilityHint(editing ? Text("Use the size and move controls") : Text(""))
    }

    private var editChrome: some View {
        HStack(spacing: 5) {
            // Keyboard/VoiceOver reorder alternatives to drag.
            iconButton("chevron.up", "Move up", onMoveUp)
            iconButton("chevron.down", "Move down", onMoveDown)
            if canResize {
                Menu {
                    ForEach(module.descriptor.supportedSizes) { s in
                        Button(s.label) { onResize(s) }
                    }
                } label: { Image(systemName: "square.resize").font(.system(size: 10)).padding(4)
                    .background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white) }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Resize \(module.descriptor.name)")
            }
            Button { onRemove() } label: {
                Image(systemName: "minus.circle.fill").font(.system(size: 12))
                    .foregroundStyle(DesignTokens.Palette.statusFailure)
            }.buttonStyle(.plain).accessibilityLabel("Remove \(module.descriptor.name) from More")
        }
        .padding(5)
    }

    private func iconButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .semibold)).padding(4)
                .background(.black.opacity(0.5), in: Circle()).foregroundStyle(.white)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}
