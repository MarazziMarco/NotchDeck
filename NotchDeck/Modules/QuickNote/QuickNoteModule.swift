import SwiftUI
import SharedWidgets

struct QuickNoteModule: NotchModule {
    let id = "quickNote"
    let displayName = "Quick Note"
    let iconName = "note.text"
    let defaultEnabled = true
    let defaultHomeFavorite = false      // available, not on Home by default
    let defaultDashboardSize: ModuleDashboardSize = .medium
    let supportedSizes: [ModuleDashboardSize] = [.small, .medium, .large]
    let defaultPriority = 50
    let defaultGroup: ModuleGroup = .home

    func makeDashboardCard(size: ModuleDashboardSize) -> AnyView {
        AnyView(NotchNoteFlip { QuickNoteCard(size: size) })
    }
    func makeFocusView() -> AnyView { AnyView(NotchNoteFlip { QuickNoteFocusView() }) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .large]
    let defaultWidgetSize: DashboardWidgetSize = .medium
    let preferredStyle: DashboardWidgetStyle = .sheet
    let canLiveActivity = false
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(NotchNoteFlip { QuickNoteWidget(size: size) }) }
}

struct QuickNoteCard: View {
    let size: ModuleDashboardSize
    @EnvironmentObject private var service: QuickNoteService

    var body: some View {
        if size == .small {
            ModuleSummaryCard(icon: "note.text", title: "Note",
                              value: nil,
                              subtitle: service.isEmpty ? "Empty" : service.firstLine,
                              tint: .neutral, compact: true)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Quick Note", accessory: service.isEmpty ? nil : "\(service.wordCount) words")
                Text(service.isEmpty ? "Tap to write a quick note…" : service.text)
                    .font(.system(size: 11))
                    .foregroundStyle(service.isEmpty ? DesignTokens.Palette.tertiaryText
                                                     : DesignTokens.Palette.primaryText)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .lineLimit(size == .large ? 8 : 3)
            }
            .dashboardCard()
        }
    }
}

struct QuickNoteFocusView: View {
    @EnvironmentObject private var service: QuickNoteService

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Quick Note", systemImage: "note.text")
                    .font(.headline).foregroundStyle(DesignTokens.Palette.primaryText)
                Spacer()
                if !service.isEmpty {
                    Button("Clear") { service.text = "" }
                        .buttonStyle(.borderless).controlSize(.small)
                }
            }
            WidgetTextEditor(text: $service.text, ink: NSColor(DesignTokens.Palette.primaryText), font: .systemFont(ofSize: 14))
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(DesignTokens.Palette.cardFill,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            if let error = service.sharingError {
                Text(error).font(.caption2).foregroundStyle(.red)
            }
            Text("Shared with LaunchPad on this Mac.")
                .font(.caption2).foregroundStyle(DesignTokens.Palette.tertiaryText)
        }
        .padding(DesignTokens.Metrics.contentPadding)
    }
}

struct NotchNoteFlip<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ObservedObject private var channel = SharedWidgetLibrary.shared.note
    @EnvironmentObject private var settings: SettingsStore
    @State private var flipped = false
    @State private var draft = SharedNote()
    var body: some View {
        WidgetFlipCard(title: "Nota rapida", symbol: "note.text", flipped: $flipped,
                       onEdit: { draft = channel.value; flipped = true },
                       onSave: { try channel.update { $0.title = draft.title; $0.color = draft.color } }, front: content) {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Titolo", text: $draft.title).textFieldStyle(.roundedBorder)
                Picker("Colore", selection: $draft.color) {
                    Text("Giallo").tag("yellow"); Text("Pesca").tag("peach")
                    Text("Menta").tag("mint"); Text("Lavanda").tag("lavender")
                }
                Text("Il testo si salva mentre scrivi ed è condiviso con LaunchPad.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear { applyColor(channel.value.color) }
        .onChange(of: channel.value.color) { _, color in applyColor(color) }
    }
    private func applyColor(_ name: String) {
        let rgb: (Double, Double, Double)
        switch name {
        case "peach": rgb = (1, 0.73, 0.57)
        case "mint": rgb = (0.69, 0.87, 0.71)
        case "lavender": rgb = (0.81, 0.76, 0.94)
        default: rgb = (1, 0.88, 0.42)
        }
        let color = NotePaperColor(red: rgb.0, green: rgb.1, blue: rgb.2)
        if settings.settings.resolvedNotePaperColor != color { settings.settings.selectCustomNoteColor(color) }
    }
}
