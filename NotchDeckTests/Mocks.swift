import Foundation
import AppKit
@testable import NotchDeck

/// Test doubles required by the spec.

struct MockCameraPermissionService: CameraPermissionProviding {
    var _status: PermissionStatus
    var requestResult: PermissionStatus
    var status: PermissionStatus { _status }
    func request() async -> PermissionStatus { requestResult }
}

struct MockAccessibilityService: AccessibilityControlling {
    var trusted: Bool = false
    var windows: [ExternalWindowInfo] = []
    var apps: [Any] = []
    var isTrusted: Bool { trusted }
    func requestPermission() {}
    func runningAgentCandidateApps() -> [NSRunningApplication] { [] }
    func windows(for app: NSRunningApplication) -> [ExternalWindowInfo] { windows }
    func raise(_ window: ExternalWindowInfo) -> Bool { true }
    func activateApp(pid: pid_t) -> Bool { true }
}

struct MockNotificationService: NotificationServing {
    func status() async -> PermissionStatus { .granted }
    func request() async -> PermissionStatus { .granted }
    func notify(title: String, body: String) {}
}

/// In-memory pasteboard reader for clipboard tests.
final class MockPasteboard: PasteboardReading {
    var changeCount: Int = 0
    var typeNames: [String] = []
    var strings: [NSPasteboard.PasteboardType: String] = [:]
    var datas: [NSPasteboard.PasteboardType: Data] = [:]
    func string(forType type: NSPasteboard.PasteboardType) -> String? { strings[type] }
    func data(forType type: NSPasteboard.PasteboardType) -> Data? { datas[type] }
}

/// Captures restores instead of touching the system pasteboard.
final class MockPasteboardWriter: PasteboardWriting {
    var restored: [ClipboardItem] = []
    func restore(_ item: ClipboardItem) { restored.append(item) }
}
