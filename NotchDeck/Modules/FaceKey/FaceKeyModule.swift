import AppKit
import SwiftUI

/// FaceKey as a top-level NotchDeck workspace (shown beside Utilities and
/// Agents) — but only while the separate FaceKey app is running and the module
/// is enabled. NotchDeck never handles the camera, keys, recognition, or file
/// encryption; the workspace only opens the FaceKey app at the right screen
/// through the `facekey://` URL scheme.
enum FaceKeyModule {
    static let identifier = "built-in.facekey"

    static let descriptor = ModuleDescriptor(
        identifier: identifier,
        displayName: "FaceKey",
        summary: "Verify your face and protect files with the FaceKey app.",
        version: "1.0.0",
        author: "FaceKey",
        category: .system,
        iconSystemName: "person.crop.circle.badge.checkmark",
        defaultEnabled: true,
        surfaces: [.workspace, .settingsSection],
        capabilities: [],
        hasSettings: true)

    /// Enabled only when the toggle is on AND the FaceKey app is currently
    /// running, so the workspace appears while FaceKey runs and disappears the
    /// moment it quits.
    static func isEnabled(_ settings: AppSettings) -> Bool {
        ModuleEnablement.isEnabled(identifier, defaultEnabled: descriptor.defaultEnabled, settings: settings)
            && FaceKeyPresence.isRunning
    }

    /// The FaceKey deep links this workspace can open. Pure and testable.
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

/// Detects whether the separate FaceKey application is currently running.
enum FaceKeyPresence {
    static let bundleIdentifier = "com.marazzimarco.FaceKey"

    static var isRunning: Bool {
        NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleIdentifier }
    }
}

/// Opens FaceKey deep links. Isolated so views stay testable.
enum FaceKeyLauncher {
    static func open(_ action: FaceKeyModule.Action) {
        guard let url = action.url else { return }
        NSWorkspace.shared.open(url)
    }
}

/// The FaceKey workspace surface (rendered by `ExpandedNotchView`).
struct FaceKeyWorkspaceView: View {
    private let primaryActions: [FaceKeyModule.Action] = [.verify, .protectFiles, .openContainer]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("FaceKey")
                .font(.system(size: 13, weight: .semibold))
            Text("Local face verification and an encrypted file vault, in the separate FaceKey app.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ForEach(primaryActions, id: \.self) { action in
                Button { FaceKeyLauncher.open(action) } label: {
                    Label(action.title, systemImage: action.systemImage)
                        .font(.system(size: 12))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 8)
                        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(action.title)
            }

            HStack {
                Button { FaceKeyLauncher.open(.settings) } label: {
                    Label(FaceKeyModule.Action.settings.title, systemImage: "gearshape")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FaceKeyModule.Action.settings.title)
                Spacer(minLength: 0)
            }

            Text("Opens the FaceKey app. NotchDeck never handles your camera, keys, or files.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct FaceKeyModuleSettings: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FaceKey runs as its own app. This workspace only opens FaceKey at the right screen; it never receives camera frames, face data, passwords, or keys. It appears only while the FaceKey app is running.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Open FaceKey Settings") { FaceKeyLauncher.open(.settings) }
        }
    }
}
