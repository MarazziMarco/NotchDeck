import ServiceManagement

/// Wraps `SMAppService` for launch-at-login. Falls back gracefully on failure.
enum LoginItemService {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            Log.app.error("Login item toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
