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
        AnyView(QuickNoteCard(size: size))
    }
    func makeFocusView() -> AnyView { AnyView(QuickNoteFocusView()) }

    let supportedWidgetSizes: [DashboardWidgetSize] = [.small, .medium, .large]
    let defaultWidgetSize: DashboardWidgetSize = .medium
    let preferredStyle: DashboardWidgetStyle = .sheet
    let canLiveActivity = false
    func makeWidget(size: DashboardWidgetSize) -> AnyView { AnyView(QuickNoteWidget(size: size)) }
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
