import AppKit
import SwiftUI

/// A thin FaceKey presence inside NotchDeck. NotchDeck never handles the camera,
/// keys, recognition, or file encryption — the separate, independently signed
/// FaceKey app owns all of that. This module only shows concise entry points and
/// opens the FaceKey app at the right destination through the `facekey://` URL
/// scheme. Live sanitized progress inside NotchDeck is a later, IPC-gated step.
struct FaceKeyModule: NotchDeckModule {
    static let descriptor = ModuleDescriptor(
        identifier: "built-in.facekey",
        displayName: "FaceKey",
        summary: "Verify your face and protect files with the FaceKey app.",
        version: "1.0.0",
        author: "FaceKey",
        category: .system,
        iconSystemName: "person.crop.circle.badge.checkmark",
        defaultEnabled: false,
        surfaces: [.more, .expandedTab, .settingsSection],
        capabilities: [],
        hasSettings: true)

    init() {}

    func moreCard(context: ModuleContext) -> AnyView? { AnyView(FaceKeyModuleCard()) }
    func expandedView(context: ModuleContext) -> AnyView? { AnyView(FaceKeyModuleCard()) }
    func settingsView(context: ModuleContext) -> AnyView? { AnyView(FaceKeyModuleSettings()) }

    /// The FaceKey deep links this module can open. Pure and testable.
    enum Action: String, CaseIterable {
        case verify
        case protectFiles = "protect"
        case openContainer = "open"
        case settings

        var url: URL? { URL(string: "facekey://\(rawValue)") }

        var title: String {
            switch self {
            case .verify: return "Verify Face"
            case .protectFiles: return "Protect File or Folder"
            case .openContainer: return "Open FaceKey Container"
            case .settings: return "Open FaceKey Settings"
            }
        }

        var systemImage: String {
            switch self {
            case .verify: return "faceid"
            case .protectFiles: return "lock.doc"
            case .openContainer: return "tray.and.arrow.up"
            case .settings: return "gearshape"
            }
        }
    }
}

struct FaceKeyModuleCard: View {
    private let primaryActions: [FaceKeyModule.Action] = [.verify, .protectFiles, .openContainer]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .accessibilityHidden(true)
                Text("FaceKey")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
            }
            ForEach(primaryActions, id: \.self) { action in
                Button { FaceKeyLauncher.open(action) } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.system(size: 11))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }
            Divider().opacity(0.4)
            Button { FaceKeyLauncher.open(.settings) } label: {
                Label(FaceKeyModule.Action.settings.title, systemImage: "gearshape")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(FaceKeyModule.Action.settings.title)
            Text("Opens the FaceKey app. NotchDeck never handles your camera, keys, or files.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FaceKeyModuleSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FaceKey runs as its own app. This module only opens FaceKey at the right screen; it never receives camera frames, face data, passwords, or keys.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open FaceKey Settings") { FaceKeyLauncher.open(.settings) }
        }
    }
}

/// Opens FaceKey deep links. Isolated so the module views stay testable.
enum FaceKeyLauncher {
    static func open(_ action: FaceKeyModule.Action) {
        guard let url = action.url else { return }
        NSWorkspace.shared.open(url)
    }
}
