import SwiftUI

/// In-panel module library overlay (not a separate app window). Lists every
/// registered module and lets the user open it, add/remove from Home, reorder,
/// choose a size, enable/disable, and open its settings.
struct ModuleLibraryView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ZStack {
            // Dim + dismiss on background tap (does not pin).
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { appState.showingModuleLibrary = false }

            VStack(spacing: 0) {
                header
                Divider().overlay(DesignTokens.Palette.separator)
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(registry.allModules, id: \.id) { module in
                            ModuleLibraryRow(module: module)
                        }
                    }
                    .padding(12)
                }
            }
            .background(DesignTokens.Palette.expandedSurfaceRaised)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(DesignTokens.Palette.hairline, lineWidth: 0.6))
            .padding(16)
        }
    }

    private var header: some View {
        HStack {
            Text("Modules").font(.headline).foregroundStyle(DesignTokens.Palette.primaryText)
            Spacer()
            Button("Done") { appState.showingModuleLibrary = false }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.statusRunning)
        }
        .padding(12)
    }
}

struct ModuleLibraryRow: View {
    let module: NotchModule
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState

    private var enabled: Bool { registry.isEnabled(module) }
    private var favorite: Bool { registry.isHomeFavorite(module) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: module.iconName)
                .frame(width: 22).foregroundStyle(DesignTokens.Palette.secondaryText)
            VStack(alignment: .leading, spacing: 1) {
                Text(module.displayName).font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DesignTokens.Palette.primaryText)
                if !module.isAvailable {
                    Text("Unavailable").font(.caption2).foregroundStyle(.orange)
                }
            }
            Spacer()

            if enabled {
                // Size picker
                Picker("", selection: Binding(
                    get: { registry.size(for: module) },
                    set: { registry.setSize(module, $0) })) {
                    ForEach(module.supportedSizes) { Text($0.label.prefix(1)).tag($0) }
                }
                .labelsHidden().frame(width: 54).controlSize(.mini)

                Button(favorite ? "On Home" : "Add") {
                    favorite ? registry.removeFromHome(module) : registry.addToHome(module)
                }
                .buttonStyle(.plain).controlSize(.small)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(favorite ? DesignTokens.Palette.statusSuccess : DesignTokens.Palette.secondaryText)

                Button("Open") {
                    appState.focusModule(module.id)
                }
                .buttonStyle(.plain).controlSize(.small).font(.system(size: 10, weight: .medium))
                .foregroundStyle(DesignTokens.Palette.statusRunning)
            }

            Toggle("", isOn: Binding(
                get: { enabled },
                set: { registry.toggleEnabled(module, $0) }))
                .labelsHidden().controlSize(.mini)
        }
        .padding(8)
        .background(DesignTokens.Palette.cardFill,
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
