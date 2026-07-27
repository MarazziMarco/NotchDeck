import SwiftUI

/// Focus Mode for a module: a back button + the module's full focused view.
/// Uses most of the panel, never pins, and preserves module state (services
/// keep their data) when returning to Home.
struct FocusContainer: View {
    let moduleID: String
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            FocusBackBar(title: registry.module(id: moduleID)?.displayName ?? "Module") {
                appState.clearFocus()
            }
            if let module = registry.module(id: moduleID) {
                module.makeFocusView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                Text("Module unavailable").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

/// Slim back bar used by all focus views.
struct FocusBackBar: View {
    let title: String
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 6) {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    Text("Home").font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(DesignTokens.Palette.secondaryText)
            }
            .buttonStyle(.plain)
            Spacer()
            Text(title).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.Palette.tertiaryText)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
