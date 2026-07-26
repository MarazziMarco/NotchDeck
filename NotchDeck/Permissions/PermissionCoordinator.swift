import AppKit
import Combine

/// Central place to query and request the app's permissions, and to publish
/// their live status to the Settings UI. Requests are always contextual — this
/// type never prompts on its own; callers ask when a feature needs access.
@MainActor
final class PermissionCoordinator: ObservableObject {
    @Published var camera: PermissionStatus = .notDetermined
    @Published var accessibility: PermissionStatus = .notDetermined
    @Published var notifications: PermissionStatus = .notDetermined

    private let cameraService: CameraPermissionProviding
    private let notificationService: NotificationServing
    private let accessibilityService: AccessibilityControlling

    init(camera: CameraPermissionProviding = CameraPermissionService(),
         notifications: NotificationServing = NotificationService(),
         accessibility: AccessibilityControlling = AccessibilityService()) {
        self.cameraService = camera
        self.notificationService = notifications
        self.accessibilityService = accessibility
    }

    func refresh() async {
        camera = cameraService.status
        accessibility = accessibilityService.isTrusted ? .granted : .notDetermined
        notifications = await notificationService.status()
    }

    func status(for permission: AppPermission) -> PermissionStatus {
        switch permission {
        case .camera: return camera
        case .accessibility: return accessibility
        case .notifications: return notifications
        }
    }

    @discardableResult
    func request(_ permission: AppPermission) async -> PermissionStatus {
        switch permission {
        case .camera:
            camera = await cameraService.request()
            return camera
        case .notifications:
            notifications = await notificationService.request()
            return notifications
        case .accessibility:
            // Accessibility can't be granted programmatically; open the prompt
            // and let the user grant it in System Settings.
            accessibilityService.requestPermission()
            accessibility = accessibilityService.isTrusted ? .granted : .notDetermined
            return accessibility
        }
    }

    func openSystemSettings(for permission: AppPermission) {
        let anchor: String
        switch permission {
        case .camera: anchor = "Privacy_Camera"
        case .accessibility: anchor = "Privacy_Accessibility"
        case .notifications:
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            return
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
