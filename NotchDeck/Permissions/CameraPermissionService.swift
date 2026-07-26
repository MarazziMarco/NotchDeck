import AVFoundation

/// Camera authorization, behind a protocol so Mirror can be tested with a mock.
protocol CameraPermissionProviding {
    var status: PermissionStatus { get }
    func request() async -> PermissionStatus
}

struct CameraPermissionService: CameraPermissionProviding {
    var status: PermissionStatus {
        Self.map(AVCaptureDevice.authorizationStatus(for: .video))
    }

    func request() async -> PermissionStatus {
        if status == .granted { return .granted }
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        return granted ? .granted : .denied
    }

    static func map(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
