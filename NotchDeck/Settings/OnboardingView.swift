import SwiftUI

/// Very short first-run onboarding. Explains the product, lets the user pick
/// modules, and only mentions permissions the chosen modules need — it never
/// prompts for Camera or Accessibility up front.
struct OnboardingView: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var settings: SettingsStore
    let onFinish: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 16) {
            content
            Spacer()
            HStack {
                if step > 0 { Button("Back") { step -= 1 } }
                Spacer()
                Button(step < lastStep ? "Continue" : "Get Started") {
                    if step < lastStep { step += 1 } else { onFinish() }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private let lastStep = 2

    @ViewBuilder private var content: some View {
        switch step {
        case 0:
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "rectangle.topthird.inset.filled").font(.system(size: 44))
                Text("Welcome to NotchDeck").font(.largeTitle).fontWeight(.semibold)
                Text("An unobtrusive surface around your notch. Two faces: everyday Utilities, and control for your coding agents. Everything stays on this Mac.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        case 1:
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose your modules").font(.title2).fontWeight(.semibold)
                ForEach(registry.allModules, id: \.id) { module in
                    Toggle(isOn: Binding(
                        get: { registry.isEnabled(module) },
                        set: { registry.toggleEnabled(module, $0) })) {
                        Label(module.displayName, systemImage: module.iconName)
                    }
                }
                Text("Permissions are requested later, only when a module needs them.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                Text("You're all set").font(.title2).fontWeight(.semibold)
                Label("Camera is requested when you first open Mirror.", systemImage: "web.camera")
                Label("Accessibility is requested when you enable external window control.", systemImage: "macwindow")
                Label("Notifications are requested when you enable Pomodoro.", systemImage: "bell")
                Text("Configure coding agents anytime in Settings › Coding Agents.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .labelStyle(.titleAndIcon)
        }
    }
}
