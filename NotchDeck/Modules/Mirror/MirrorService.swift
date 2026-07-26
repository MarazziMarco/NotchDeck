import AVFoundation
import AppKit
import Combine

/// Owns the AVFoundation capture session for the Mirror module. Session
/// configuration runs on a dedicated queue; published state is republished on
/// the main queue. Only alive while the module is visible.
/// No recording, no audio, no frames written to disk, no network.
final class MirrorService: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case running
        case denied
        case unavailable(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var availableCameras: [AVCaptureDevice] = []
    @Published private(set) var selectedDeviceID: String?
    /// Logical on/off set by tapping the Mirror card. Persists across notch
    /// close (the session stops for privacy/power but restarts on reopen while
    /// still enabled). Off frees the session and won't restart.
    @Published private(set) var isEnabled: Bool = false

    let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.notchdeck.mirror.session")
    private let permission: CameraPermissionProviding
    private var currentInput: AVCaptureDeviceInput?

    init(permission: CameraPermissionProviding = CameraPermissionService()) {
        self.permission = permission
        super.init()
    }

    var permissionStatus: PermissionStatus { permission.status }

    private func setState(_ new: State) {
        DispatchQueue.main.async { self.state = new }
    }

    func refreshCameras() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video, position: .unspecified)
        let devices = discovery.devices
        DispatchQueue.main.async { self.availableCameras = devices }
    }

    /// Begin the preview, requesting permission first if needed.
    func start() async {
        refreshCameras()
        switch permission.status {
        case .denied, .restricted:
            setState(.denied); return
        case .notDetermined:
            let result = await permission.request()
            guard result == .granted else { setState(.denied); return }
        case .granted:
            break
        }
        configureAndRun(deviceID: selectedDeviceID)
    }

    func stop() {
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
        setState(.idle)
    }

    /// Toggle the Mirror on/off from the card. Turning on starts the preview
    /// (requesting permission if needed); turning off stops and frees the session.
    func toggle() {
        if isEnabled {
            isEnabled = false
            stop()
        } else {
            isEnabled = true
            Task { await start() }
        }
    }

    /// Called when the Mirror card becomes visible: (re)start if still enabled.
    func activateIfEnabled() async {
        guard isEnabled else { return }
        await start()
    }

    /// Called when the Mirror card disappears (notch closed): stop the session
    /// for privacy/power but keep the logical enabled state.
    func deactivateForHidden() {
        stop()
    }

    func selectCamera(id: String) {
        DispatchQueue.main.async { self.selectedDeviceID = id }
        configureAndRun(deviceID: id)
    }

    private func configureAndRun(deviceID: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            let device = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                mediaType: .video, position: .unspecified)
                .devices.first(where: { $0.uniqueID == deviceID })
                ?? AVCaptureDevice.default(for: .video)
            guard let device else {
                self.setState(.unavailable("No camera found"))
                return
            }
            self.session.beginConfiguration()
            self.session.sessionPreset = .high
            if let existing = self.currentInput {
                self.session.removeInput(existing)
                self.currentInput = nil
            }
            do {
                let input = try AVCaptureDeviceInput(device: device)
                if self.session.canAddInput(input) {
                    self.session.addInput(input)
                    self.currentInput = input
                }
            } catch {
                self.session.commitConfiguration()
                self.setState(.unavailable(error.localizedDescription))
                return
            }
            self.session.commitConfiguration()
            if !self.session.isRunning { self.session.startRunning() }
            let resolvedID = device.uniqueID
            DispatchQueue.main.async {
                self.selectedDeviceID = resolvedID
                self.state = .running
            }
        }
    }
}
