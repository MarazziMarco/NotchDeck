import SwiftUI

/// Centred first-launch permission onboarding. A normal foreground window (NOT
/// the notch panel) so system permission dialogs are never hidden behind it.
struct PermissionsSetupView: View {
    @ObservedObject var model: PermissionsSetupModel
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 460)
    }

    private var header: some View {
        VStack(spacing: 4) {
            Text("Set Up NotchDeck").font(.system(size: 16, weight: .semibold))
            Text("Grant the permissions the modules you use need. You can skip any and change them later in Settings.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            stepDots
        }
        .padding(16)
    }

    private var stepDots: some View {
        let steps = PermissionOnboarding.steps.filter { $0.requestsPermission }
        return HStack(spacing: 6) {
            ForEach(steps) { s in
                Circle().fill(s == model.step ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: 6, height: 6)
            }
        }.padding(.top, 4)
    }

    @ViewBuilder private var content: some View {
        if model.isComplete {
            completeView
        } else {
            stepView(model.step)
        }
    }

    private func stepView(_ s: PermissionStep) -> some View {
        let state = model.state(s)
        return VStack(spacing: 14) {
            Image(systemName: icon(s)).font(.system(size: 40)).foregroundStyle(.tint)
            Text(s.title).font(.system(size: 15, weight: .semibold))
            Text(s.rationale).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
            statusBadge(state)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    private var completeView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 44)).foregroundStyle(.green)
            Text("All set").font(.system(size: 16, weight: .semibold))
            Text(PermissionStep.complete.rationale).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(20)
    }

    private func statusBadge(_ state: PermissionSetupState) -> some View {
        let (text, color): (String, Color) = {
            switch state {
            case .notRequested: return ("Not requested", .secondary)
            case .granted: return ("Granted", .green)
            case .denied: return ("Denied", .red)
            case .requiresSystemSettings: return ("Requires System Settings", .orange)
            }
        }()
        return Text(text).font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.18), in: Capsule()).foregroundStyle(color)
    }

    private var footer: some View {
        HStack {
            Button("Skip for Now") { model.skip() }.buttonStyle(.plain).foregroundStyle(.secondary)
            Spacer()
            if model.isComplete {
                Button("Done") { model.finish(); onClose() }.keyboardShortcut(.defaultAction)
            } else {
                let state = model.state(model.step)
                if PermissionOnboarding.offersSystemSettings(state) {
                    Button("Open System Settings") { model.openSystemSettings(for: model.step) }
                }
                if PermissionOnboarding.shouldRequest(model.step, state: state) {
                    Button("Grant") { model.request(model.step) }
                        .keyboardShortcut(.defaultAction).disabled(model.busy)
                } else {
                    Button("Continue") { model.advanceAfterRequest() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(16)
    }

    private func icon(_ s: PermissionStep) -> String {
        switch s {
        case .camera: return "web.camera"
        case .screenRecording: return "rectangle.dashed.badge.record"
        case .downloads: return "arrow.down.circle"
        case .terminalAutomation: return "macwindow.on.rectangle"
        default: return "checkmark"
        }
    }
}
