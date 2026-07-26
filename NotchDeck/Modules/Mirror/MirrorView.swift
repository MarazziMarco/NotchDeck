import SwiftUI
import AVFoundation

/// SwiftUI wrapper around `AVCaptureVideoPreviewLayer`, aspect-fill, with
/// panel-consistent corners. The horizontal mirror is applied deterministically
/// and RE-ASSERTED on every update and layout pass, so it survives session
/// restarts, toggles and reopen (the preview connection is recreated when the
/// session reconfigures, which is why setting it only once was intermittent).
struct CameraPreviewView: NSViewRepresentable {
    let session: AVCaptureSession
    /// Default is a true mirror (horizontally flipped).
    var mirrored: Bool = true

    func makeNSView(context: Context) -> PreviewNSView {
        let view = PreviewNSView()
        view.previewLayer.videoGravity = .resizeAspectFill
        view.apply(session: session, mirrored: mirrored)
        return view
    }

    func updateNSView(_ nsView: PreviewNSView, context: Context) {
        nsView.apply(session: session, mirrored: mirrored)
    }

    final class PreviewNSView: NSView {
        let previewLayer = AVCaptureVideoPreviewLayer()
        private var desiredMirrored = true

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer = CALayer()
            layer?.addSublayer(previewLayer)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

        func apply(session: AVCaptureSession, mirrored: Bool) {
            desiredMirrored = mirrored
            if previewLayer.session !== session { previewLayer.session = session }
            applyMirror()
        }

        /// Explicit, single-source-of-truth mirror on the preview connection.
        /// Disabling automatic adjustment prevents an accidental double-flip.
        private func applyMirror() {
            guard let connection = previewLayer.connection else { return }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = desiredMirrored
            }
        }

        override func layout() {
            super.layout()
            previewLayer.frame = bounds
            // Re-assert after the connection exists (it may be nil at make time).
            applyMirror()
        }
    }
}

/// Expanded Mirror view: preview when running, elegant placeholder otherwise.
struct MirrorExpandedView: View {
    @EnvironmentObject private var service: MirrorService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Label("Mirror", systemImage: "web.camera")
                    .font(.headline).foregroundStyle(DesignTokens.Palette.primaryText)
                Spacer()
                if service.availableCameras.count > 1 {
                    Picker("", selection: Binding(
                        get: { service.selectedDeviceID ?? "" },
                        set: { service.selectCamera(id: $0) })) {
                        ForEach(service.availableCameras, id: \.uniqueID) { cam in
                            Text(cam.localizedName).tag(cam.uniqueID)
                        }
                    }
                    .labelsHidden().frame(width: 160)
                }
            }
            preview
        }
        .padding(DesignTokens.Metrics.contentPadding)
        .task { await service.start() }
        .onDisappear { service.stop() }
    }

    @ViewBuilder private var preview: some View {
        switch service.state {
        case .running:
            CameraPreviewView(session: service.session,
                              mirrored: settings.settings.mirrorOrientation.isMirrored)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius))
        case .denied:
            placeholder(icon: "video.slash",
                        text: "Camera access denied. Enable it in System Settings › Privacy & Security › Camera.")
        case .unavailable(let why):
            placeholder(icon: "exclamationmark.triangle", text: why)
        case .idle:
            placeholder(icon: "web.camera", text: "Starting camera…")
        }
    }

    private func placeholder(icon: String, text: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.largeTitle)
            Text(text).font(.caption).multilineTextAlignment(.center)
        }
        .foregroundStyle(DesignTokens.Palette.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 200)
        .background(DesignTokens.Palette.hairline,
                    in: RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius))
    }
}

/// Compact Mirror card that behaves as a toggle: tap to turn the camera on/off.
/// While enabled it (re)starts when visible and stops when the notch closes,
/// keeping the logical on-state; turning off frees the session for good.
struct MirrorCompactCard: View {
    @EnvironmentObject private var service: MirrorService
    @EnvironmentObject private var settings: SettingsStore

    private var isOn: Bool { service.isEnabled }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SectionLabel(text: "Mirror")
                Circle()
                    .fill(isOn ? DesignTokens.Palette.statusSuccess : DesignTokens.Palette.statusIdle)
                    .frame(width: 6, height: 6)
            }
            preview
        }
        .dashboardCard()
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Metrics.cardCornerRadius, style: .continuous)
                .strokeBorder(isOn ? DesignTokens.Palette.statusSuccess.opacity(0.5) : .clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { service.toggle() }
        .task { await service.activateIfEnabled() }
        .onDisappear { service.deactivateForHidden() }
        .help(isOn ? "Tap to turn Mirror off" : "Tap to turn Mirror on")
    }

    @ViewBuilder private var preview: some View {
        switch service.state {
        case .running:
            CameraPreviewView(session: service.session,
                              mirrored: settings.settings.mirrorOrientation.isMirrored)
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        default:
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .frame(height: 96)
                .overlay {
                    VStack(spacing: 4) {
                        Image(systemName: service.state == .denied ? "video.slash"
                              : (isOn ? "hourglass" : "web.camera"))
                            .font(.title2)
                        Text(service.state == .denied ? "Denied" : (isOn ? "Starting…" : "Tap to enable"))
                            .font(.system(size: 9))
                    }
                    .foregroundStyle(DesignTokens.Palette.tertiaryText)
                }
        }
    }
}
