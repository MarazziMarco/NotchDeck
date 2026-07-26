import SwiftUI

/// Root Settings window with a sidebar of sections.
struct SettingsRootView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general = "General"
        case appearance = "Appearance"
        case modules = "Modules"
        case clipboard = "Clipboard"
        case fileShelf = "File Shelf"
        case mirror = "Mirror"
        case pomodoro = "Pomodoro"
        case agents = "Coding Agents"
        case permissions = "Permissions"
        case diagnostics = "Diagnostics"
        case about = "About"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .appearance: return "paintbrush"
            case .modules: return "square.grid.2x2"
            case .clipboard: return "doc.on.clipboard"
            case .fileShelf: return "tray.full"
            case .mirror: return "web.camera"
            case .pomodoro: return "timer"
            case .agents: return "cpu"
            case .permissions: return "lock.shield"
            case .diagnostics: return "stethoscope"
            case .about: return "info.circle"
            }
        }
    }

    @State private var selection: Section = .general

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            ScrollView {
                detail
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle(selection.rawValue)
        }
    }

    @ViewBuilder private var detail: some View {
        switch selection {
        case .general: GeneralSettingsView()
        case .appearance: AppearanceSettingsView()
        case .modules: ModulesSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .fileShelf: FileShelfSettingsView()
        case .mirror: MirrorSettingsView()
        case .pomodoro: PomodoroSettingsView()
        case .agents: AgentsSettingsView()
        case .permissions: PermissionsSettingsView()
        case .diagnostics: DiagnosticsSettingsView()
        case .about: AboutSettingsView()
        }
    }
}

/// Small helper for consistent settings section layout.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            content
        }
        .padding(.bottom, 8)
    }
}
