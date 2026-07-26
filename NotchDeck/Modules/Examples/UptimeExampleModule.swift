import SwiftUI

/// EXAMPLE community module — a template for contributors.
///
/// Demonstrates: descriptor metadata, a simple Home card, an optional settings
/// section, NO sensitive capability, registration and tests. It is NOT enabled
/// by default in production (`defaultEnabled: false`).
///
/// It shows the system uptime — read-only, no permissions, no network.
struct UptimeExampleModule: NotchDeckModule {
    static let descriptor = ModuleDescriptor(
        identifier: "com.notchdeck.example.uptime",
        displayName: "Uptime (Example)",
        summary: "Example module showing system uptime. A template for contributors.",
        version: "1.0.0",
        author: "NotchDeck",
        category: .example,
        iconSystemName: "clock.arrow.circlepath",
        defaultEnabled: false,                 // examples never ship enabled
        surfaces: [.homeCard, .settingsSection],
        capabilities: [],                      // no sensitive capability
        hasSettings: true)

    init() {}

    func homeCard(context: ModuleContext) -> AnyView? {
        AnyView(UptimeCard())
    }

    func settingsView(context: ModuleContext) -> AnyView? {
        AnyView(Text("This is an example module. It uses no permissions.")
            .font(.caption).foregroundStyle(.secondary))
    }

    /// Pure, testable uptime formatter (no Date.now dependency).
    static func formatUptime(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

private struct UptimeCard: View {
    private var uptime: String {
        UptimeExampleModule.formatUptime(ProcessInfo.processInfo.systemUptime)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Uptime", systemImage: "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            Text(uptime).font(.system(size: 20, weight: .semibold, design: .rounded))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(10)
    }
}
