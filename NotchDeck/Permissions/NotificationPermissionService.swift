import UserNotifications

/// Notification authorization + local delivery, behind a protocol for testing.
protocol NotificationServing {
    func status() async -> PermissionStatus
    func request() async -> PermissionStatus
    func notify(title: String, body: String)
}

struct NotificationService: NotificationServing {
    private var center: UNUserNotificationCenter { .current() }

    func status() async -> PermissionStatus {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    func request() async -> PermissionStatus {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            return granted ? .granted : .denied
        } catch {
            return .denied
        }
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        // Respects Do Not Disturb / Focus automatically; we never try to bypass it.
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content, trigger: nil)
        center.add(request)
    }
}
