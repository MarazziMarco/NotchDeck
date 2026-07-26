import Foundation

/// Typed errors surfaced across NotchDeck. Every integration fails through one
/// of these with a human-readable message instead of `try!` / force-unwraps.
enum NotchDeckError: LocalizedError, Equatable {
    case noDisplayAvailable
    case cameraUnavailable(String)
    case cameraPermissionDenied
    case accessibilityPermissionDenied
    case notificationPermissionDenied
    case executableNotFound(tool: String)
    case processLaunchFailed(tool: String, underlying: String)
    case processTerminated(tool: String, code: Int32)
    case protocolDecoding(String)
    case sessionNotFound
    case unsupportedOperation(String)
    case fileNoLongerAvailable(String)
    case invalidProjectPath(String)

    var errorDescription: String? {
        switch self {
        case .noDisplayAvailable:
            return "No display is available to position the notch panel."
        case .cameraUnavailable(let detail):
            return "The camera is unavailable: \(detail)"
        case .cameraPermissionDenied:
            return "Camera access is required for Mirror. Grant it in System Settings › Privacy & Security › Camera."
        case .accessibilityPermissionDenied:
            return "Accessibility access is required to detect and raise external windows."
        case .notificationPermissionDenied:
            return "Notification permission is required for Pomodoro alerts."
        case .executableNotFound(let tool):
            return "Could not find the \(tool) executable. Set its path in Settings › Coding Agents."
        case .processLaunchFailed(let tool, let underlying):
            return "Failed to launch \(tool): \(underlying)"
        case .processTerminated(let tool, let code):
            return "\(tool) exited unexpectedly with code \(code)."
        case .protocolDecoding(let detail):
            return "Could not decode agent output: \(detail)"
        case .sessionNotFound:
            return "The requested agent session no longer exists."
        case .unsupportedOperation(let detail):
            return "This operation is not supported by the installed CLI: \(detail)"
        case .fileNoLongerAvailable(let name):
            return "\(name) is no longer available at its original location."
        case .invalidProjectPath(let path):
            return "The project path is not a valid directory: \(path)"
        }
    }
}
