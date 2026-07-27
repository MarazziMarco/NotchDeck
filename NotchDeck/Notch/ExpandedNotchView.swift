import SwiftUI
import UniformTypeIdentifiers

/// The expanded surface: a slim header with the face switcher, then the active
/// face. Accepts file drops (routing to the File Shelf) and horizontal swipes
/// to switch faces.
struct ExpandedNotchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var fileShelf: FileShelfStore
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DesignTokens.Palette.separator)
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay { if appState.showingModuleLibrary { ModuleLibraryView() } }
        .overlay(dropHighlight)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onChange(of: isDropTargeted) { _, targeted in
            appState.dragInProgress = targeted
            if targeted { appState.expand(face: .utilities) }
        }
        .gesture(faceSwipe)
    }

    private var header: some View {
        HStack(spacing: 8) {
            // The Utilities | Agents workspace selector appears ONLY while the
            // Agents module is enabled. When disabled it is removed entirely — no
            // capsule, no single "Utilities" label — and Utilities is the sole
            // root workspace.
            if appState.agentsEnabled {
                FaceSwitcher(selection: Binding(
                    get: { appState.face },
                    set: { appState.toggleFace(to: $0) }))
            }
            Spacer()
            // The ONLY control that toggles the pin. Being a Button, it consumes
            // its own tap and never reaches the background click monitor.
            headerIcon(appState.isPinnedByUser ? "pin.fill" : "pin",
                       help: appState.isPinnedByUser ? "Unpin" : "Keep open",
                       active: appState.isPinnedByUser) {
                appState.setPinnedByUser(!appState.isPinnedByUser, reason: "pin button")
            }
            headerIcon("gearshape", help: "Settings") {
                SettingsWindowPresenter.shared.show()
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    private func headerIcon(_ name: String, help: String, active: Bool = false,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 11, weight: .medium))
                .frame(width: 24, height: 24)
                .background(active ? DesignTokens.Palette.cardFillHover : Color.clear, in: Circle())
                .foregroundStyle(active ? DesignTokens.Palette.primaryText
                                        : DesignTokens.Palette.secondaryText)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var content: some View {
        if let moduleID = appState.focusedModuleID {
            FocusContainer(moduleID: moduleID)
        } else if appState.focusedAgentID != nil {
            AgentFocusContainer()
        } else {
            switch appState.face {
            case .utilities: UtilitiesFaceView()
            case .agents: AgentsFaceView()
            }
        }
    }

    private var dropHighlight: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Metrics.expandedCornerRadius)
            .strokeBorder(DesignTokens.Palette.statusRunning,
                          lineWidth: isDropTargeted ? 2 : 0)
            .animation(.easeOut(duration: 0.15), value: isDropTargeted)
            .allowsHitTesting(false)
    }

    private var faceSwipe: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40 { appState.toggleFace(to: .agents) }
                else if value.translation.width > 40 { appState.toggleFace(to: .utilities) }
            }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        // A drag that started inside the File Shelf must not be re-imported.
        if ShelfDrag.isInternal(providers) { appState.dragInProgress = false; return true }
        var urls: [URL] = []
        let group = DispatchGroup()
        for provider in providers where provider.canLoadObject(ofClass: URL.self) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { urls.append(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            fileShelf.add(urls: urls)
            appState.dragInProgress = false
        }
        return true
    }
}

/// Segmented Utilities / Agents switcher with a sliding highlight.
struct FaceSwitcher: View {
    @Binding var selection: NotchFace
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            segment(.utilities, "square.grid.2x2", "Utilities")
            segment(.agents, "cpu", "Agents")
        }
        .padding(3)
        .background(Color.black.opacity(0.35), in: Capsule())
        .overlay(Capsule().strokeBorder(DesignTokens.Palette.hairline, lineWidth: 0.6))
    }

    private func segment(_ face: NotchFace, _ icon: String, _ label: String) -> some View {
        let active = selection == face
        return Button {
            selection = face
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .medium))
                Text(label).font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 11).padding(.vertical, 4.5)
            .background {
                if active {
                    Capsule().fill(DesignTokens.Palette.cardFillHover)
                        .matchedGeometryEffect(id: "faceHighlight", in: ns)
                }
            }
            .foregroundStyle(active ? DesignTokens.Palette.primaryText
                                    : DesignTokens.Palette.tertiaryText)
        }
        .buttonStyle(.plain)
    }
}
