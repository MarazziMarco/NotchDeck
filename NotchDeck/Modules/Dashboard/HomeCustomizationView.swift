import SwiftUI

enum HomeReorder {
    static func move(_ ids: [String], drag: String, onto target: String) -> [String] {
        guard drag != target,
              let from = ids.firstIndex(of: drag),
              let to = ids.firstIndex(of: target) else { return ids }
        var output = ids
        let moved = output.remove(at: from)
        output.insert(moved, at: to)
        return output
    }

    static func shift(_ ids: [String], id: String, by delta: Int) -> [String] {
        guard let index = ids.firstIndex(of: id) else { return ids }
        let destination = max(0, min(ids.count - 1, index + delta))
        guard destination != index else { return ids }
        var output = ids
        output.swapAt(index, destination)
        return output
    }
}
/// Compact, native editor backed directly by AppSettings. Every action persists
/// immediately; Done only dismisses the sheet.
struct HomeCustomizationView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var registry: ModuleRegistry
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedID: String?

    private var definitions: [HomeModuleDefinition] {
        HomeModuleEligibility.definitions(from: registry.allModules)
    }

    private var orderedDefinitions: [HomeModuleDefinition] {
        let byID = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, $0) })
        return HomeLayoutNormalizer.order(in: settings.settings, definitions: definitions)
            .compactMap { byID[$0] }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            List {
                ForEach(orderedDefinitions) { definition in
                    row(definition)
                        .dropDestination(for: String.self) { items, _ in
                            guard let source = items.first else { return false }
                            persist {
                                HomeLayoutNormalizer.move(
                                    source, before: definition.id,
                                    in: &$0, definitions: definitions)
                            }
                            return true
                        }
                }
                .onMove { source, destination in
                    persist {
                        HomeLayoutNormalizer.move(
                            from: source, to: destination,
                            in: &$0, definitions: definitions)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            Divider()
            footer
        }
        .frame(width: 540, height: 430)
        .background(DesignTokens.Palette.expandedSurface)
        .preferredColorScheme(.dark)
        .onAppear {
            settings.updateHomeLayout(definitions: definitions) { _ in }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Customize Home")
                    .font(.system(size: 15, weight: .semibold))
                Text("Choose what appears, adjust sizes, or drag to reorder.")
                    .font(.system(size: 11))
                    .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            Spacer()
            Button("Done") {
                settings.saveNow()
                dismiss()
            }
            .keyboardShortcut(.defaultAction)
        }
        .padding(16)
    }

    private func row(_ definition: HomeModuleDefinition) -> some View {
        let order = orderedDefinitions.map(\.id)
        let position = (order.firstIndex(of: definition.id) ?? 0) + 1
        let visible = HomeLayoutNormalizer.isVisible(
            definition.id, in: settings.settings, definitions: definitions)
        let selectedSize = HomeLayoutNormalizer.size(
            definition.id, in: settings.settings, definitions: definitions)
            ?? definition.defaultSize

        return HStack(alignment: .center, spacing: 11) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
                .frame(width: 18, height: 28)
                .contentShape(Rectangle())
                .draggable(definition.id)
                .accessibilityLabel("Drag \(definition.name)")

            Image(systemName: definition.icon)
                .font(.system(size: 16))
                .frame(width: 24)
                .foregroundStyle(visible ? .primary : .tertiary)

            VStack(alignment: .leading, spacing: 5) {
                Text(definition.name)
                    .font(.system(size: 12.5, weight: .medium))
                if definition.supportedSizes.count > 1 {
                    Picker("Size", selection: Binding(
                        get: { selectedSize },
                        set: { size in
                            persist {
                                HomeLayoutNormalizer.setSize(
                                    size, id: definition.id,
                                    in: &$0, definitions: definitions)
                            }
                        })) {
                            ForEach(definition.supportedSizes) { size in
                                Text(size.sizeLabel).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                        .controlSize(.small)
                        .frame(maxWidth: 235)
                        .accessibilityLabel("\(definition.name) size")
                        .accessibilityValue(selectedSize.sizeLabel)
                } else if let only = definition.supportedSizes.first {
                    Text("Size: \(only.sizeLabel)")
                        .font(.system(size: 10))
                        .foregroundStyle(DesignTokens.Palette.secondaryText)
                }
            }

            Spacer(minLength: 8)

            Toggle("Visible", isOn: Binding(
                get: { visible },
                set: { show in
                    persist {
                        HomeLayoutNormalizer.setVisible(
                            show, id: definition.id,
                            in: &$0, definitions: definitions)
                    }
                }))
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel("\(definition.name) visible")
                .accessibilityValue(visible ? "Visible" : "Hidden")
        }
        .padding(.vertical, 7)
        .opacity(visible ? 1 : 0.62)
        .contentShape(Rectangle())
        .focusable()
        .focused($focusedID, equals: definition.id)
        .onMoveCommand { direction in
            switch direction {
            case .up: shift(definition.id, by: -1)
            case .down: shift(definition.id, by: 1)
            default: break
            }
        }
        .contextMenu {
            Button("Move Up") { shift(definition.id, by: -1) }
                .disabled(position == 1)
            Button("Move Down") { shift(definition.id, by: 1) }
                .disabled(position == order.count)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(definition.name), \(visible ? "visible" : "hidden"), size \(selectedSize.sizeLabel), position \(position) of \(order.count)")
        .accessibilityActions {
            Button("Move Up") { shift(definition.id, by: -1) }
            Button("Move Down") { shift(definition.id, by: 1) }
        }
    }

    private var footer: some View {
        HStack {
            Button("Reset to Default", role: .destructive) {
                persist { HomeLayoutNormalizer.reset(&$0, definitions: definitions) }
            }
            Spacer()
        }
        .padding(16)
    }

    private func shift(_ id: String, by delta: Int) {
        persist {
            HomeLayoutNormalizer.move(
                id, by: delta, in: &$0, definitions: definitions)
        }
    }

    private func persist(_ update: (inout AppSettings) -> Void) {
        withAnimation(.easeInOut(duration: 0.16)) {
            settings.updateHomeLayout(definitions: definitions, update)
        }
    }
}
