import Foundation

extension Notification.Name {
    /// View-owned module services use this to stop work before process teardown.
    static let notchDeckWillTerminate = Notification.Name("NotchDeckWillTerminate")
}

/// Injectable operations executed by the established AppDelegate termination
/// lifecycle. The sequence owns no services and cannot delete hooks or shelf
/// data; each operation routes to an existing public lifecycle entry point.
struct ApplicationShutdownOperations {
    let flushSettings: () -> Void
    let stopModuleRefreshLoops: () -> Void
    let stopTransientObservers: () -> Void
    let endFileShelfSession: () -> Void
    let resetPomodoro: () -> Void
    let requestBridgeShutdown: () -> Void
}

enum ApplicationShutdownSequence {
    static func perform(_ operations: ApplicationShutdownOperations) {
        operations.flushSettings()
        operations.stopModuleRefreshLoops()
        operations.stopTransientObservers()
        operations.endFileShelfSession()
        operations.resetPomodoro()
        operations.requestBridgeShutdown()
    }
}
