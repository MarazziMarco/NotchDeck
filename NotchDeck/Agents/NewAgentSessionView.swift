import SwiftUI
import AppKit

/// Sheet to configure and launch a new managed agent session.
struct NewAgentSessionView: View {
    @EnvironmentObject private var coordinator: AgentCoordinator
    @Environment(\.dismiss) private var dismiss

    let onStart: (AgentProviderKind, URL, String) -> Void

    @State private var provider: AgentProviderKind = .codex
    @State private var projectURL: URL?
    @State private var prompt: String = ""

    private var installedProviders: [AgentProviderKind] {
        [.codex, .claudeCode].filter { coordinator.availability[$0]?.isInstalled ?? false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Agent Session").font(.headline)

            Picker("Provider", selection: $provider) {
                ForEach(installedProviders.isEmpty ? [.codex, .claudeCode] : installedProviders) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }

            HStack {
                Text("Project").frame(width: 70, alignment: .leading)
                Text(projectURL?.path ?? "None selected")
                    .lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…", action: chooseFolder)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Initial prompt")
                TextEditor(text: $prompt)
                    .font(.callout)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
            }

            if let availability = coordinator.availability[provider], !availability.isInstalled {
                Label("\(provider.displayName) CLI not found. Set its path in Settings.",
                      systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Start") { start() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(projectURL == nil)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { projectURL = panel.url }
    }

    private func start() {
        guard let url = projectURL else { return }
        onStart(provider, url, prompt)
        dismiss()
    }
}
