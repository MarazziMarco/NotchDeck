import AppKit

@MainActor
protocol ApplicationTerminating: AnyObject {
    func terminateApplication()
}

@MainActor
private final class NSApplicationTerminator: ApplicationTerminating {
    func terminateApplication() {
        NSApplication.shared.terminate(nil)
    }
}

@MainActor
protocol ApplicationTerminationRequesting {
    func requestTermination()
}

/// Injectable boundary for requesting real application termination. Cleanup is
/// intentionally left to AppDelegate's established application lifecycle.
@MainActor
final class ApplicationTerminationCoordinator: ApplicationTerminationRequesting {
    static let shared = ApplicationTerminationCoordinator(
        application: NSApplicationTerminator())

    private let application: ApplicationTerminating

    init(application: ApplicationTerminating) {
        self.application = application
    }

    func requestTermination() {
        application.terminateApplication()
    }
}

enum SettingsPersistentAction: CaseIterable, Equatable {
    case quit

    var label: String { "Quit NotchDeck" }
    var icon: String { "power" }
    var accessibilityLabel: String { "Quit NotchDeck" }
    var isDestructive: Bool { true }

    static func actions(in section: SettingsRootView.Section) -> [SettingsPersistentAction] {
        []
    }
}
