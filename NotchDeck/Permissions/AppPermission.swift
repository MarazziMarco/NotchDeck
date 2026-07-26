import Foundation

/// System permissions NotchDeck may request. Requested lazily, only when the
/// feature that needs them is first used.
enum AppPermission: String, CaseIterable, Identifiable {
    case camera
    case accessibility
    case notifications
    var id: String { rawValue }

    var title: String {
        switch self {
        case .camera: return "Camera"
        case .accessibility: return "Accessibility"
        case .notifications: return "Notifications"
        }
    }

    var explanation: String {
        switch self {
        case .camera:
            return "Used by the Mirror module to show a live preview. Video is never recorded, saved or sent anywhere."
        case .accessibility:
            return "Lets NotchDeck detect and bring external agent windows (Terminal, iTerm2, VS Code…) to the front. It never reads screen pixels."
        case .notifications:
            return "Lets the Pomodoro timer notify you when a work or break interval ends."
        }
    }
}

/// Live status of a permission.
enum PermissionStatus: Equatable {
    case notDetermined
    case denied
    case granted
    case restricted

    var isGranted: Bool { self == .granted }
}
