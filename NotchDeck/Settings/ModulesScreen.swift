import SwiftUI

/// The Modules management screen: search, filter, module rows, and a detail
/// sheet. Source-integrated (no marketplace, no runtime plugins).
struct ModulesScreen: View {
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var community: CommunityModuleRegistry
    @EnvironmentObject private var settings: SettingsStore

    @State private var search = ""
    @State private var filter: ModuleCatalog.Filter = .all
    @State private var detailID: String?

    /// Built fresh from the authoritative registries — no parallel state.
    private var catalog: ModuleCatalog {
        ModuleCatalog(
            builtIn: registry.allModules.map { m in
                LegacyModuleAdapter.descriptor(
                    id: m.id, name: m.displayName, icon: m.iconName,
                    defaultEnabled: m.defaultEnabled, hasSettings: Self.legacyHasSettings(m.id))
            }
            // Agents is a built-in TOP-LEVEL WORKSPACE (not a Home card / tab).
            + [AgentsModule.descriptor],
            community: community.descriptors,
            example: [UptimeExampleModule.descriptor],
            includeExample: Self.showExamples(settings.settings.showDeveloperModules))
    }

    /// Example modules surface only in Debug builds or when the developer toggle
    /// is on — never to ordinary users in a Release build.
    private static func showExamples(_ developerToggle: Bool) -> Bool {
        #if DEBUG
        return true
        #else
        return developerToggle
        #endif
    }

    private var rows: [ModuleCatalogEntry] {
        catalog.filtered(search: search, filter: filter) { isEnabled($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            controls
            Text("Community modules are reviewed and compiled with NotchDeck. External runtime plugins are not currently loaded.")
                .font(.caption2).foregroundStyle(.tertiary)
            if rows.isEmpty { emptyState } else { list }
            footer
        }
        .sheet(item: Binding(get: { detailID.flatMap { catalog.entry(id: $0) } },
                             set: { detailID = $0?.id })) { entry in
            ModuleDetailSheet(entry: entry, isEnabled: isEnabled(entry),
                              setEnabled: { setEnabled(entry, $0) })
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Modules").font(.title2.bold())
            Text("Enable modules and configure them. Built-in modules ship with NotchDeck; community modules are reviewed and compiled in.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search modules", text: $search).textFieldStyle(.plain)
                if !search.isEmpty {
                    Button { search = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
            .padding(6).background(.quaternary, in: RoundedRectangle(cornerRadius: 7))
            .frame(maxWidth: 260)
            Picker("", selection: $filter) {
                ForEach(ModuleCatalog.Filter.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: 320)
            Spacer()
        }
    }

    private var list: some View {
        List(rows) { entry in
            ModuleRow(entry: entry, isEnabled: isEnabled(entry),
                      setEnabled: { setEnabled(entry, $0) })
            .contentShape(Rectangle())
            .onTapGesture { detailID = entry.id }
        }
        .listStyle(.inset).frame(minHeight: 260)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.grid.2x2").font(.system(size: 28)).foregroundStyle(.tertiary)
            Text("No modules match “\(search)”.").foregroundStyle(.secondary)
            Button("Clear Search") { search = ""; filter = .all }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var footer: some View {
        HStack {
            Toggle("Show developer/example modules", isOn: $settings.settings.showDeveloperModules)
                .toggleStyle(.switch).controlSize(.small)
            Spacer()
            Button("Learn how to create a module") {
                if let url = URL(string: "https://github.com/MarazziMarco/NotchDeck/blob/main/docs/modules/CREATING_A_MODULE.md") {
                    NSWorkspace.shared.open(url)
                }
            }.controlSize(.small)
        }
    }

    // MARK: Enablement (one authoritative source)

    private func isEnabled(_ entry: ModuleCatalogEntry) -> Bool {
        ModuleEnablement.isEnabled(entry.id, defaultEnabled: entry.descriptor.defaultEnabled,
                                   settings: settings.settings)
    }
    private func setEnabled(_ entry: ModuleCatalogEntry, _ enabled: Bool) {
        // Legacy built-ins route through the existing registry (drives Home).
        if entry.source == .builtIn, let m = registry.module(id: entry.id) {
            registry.toggleEnabled(m, enabled)
        } else {
            ModuleEnablement.setEnabled(entry.id, enabled, isHomeModule: entry.isHomeModule,
                                        defaultOrder: EditorialHomeLayout.defaultOrder,
                                        in: &settings.settings)
        }
    }

    static func legacyHasSettings(_ id: String) -> Bool {
        ["clipboard", "fileShelf", "mirror", "pomodoro", "downloads"].contains(id)
    }
}

/// A restrained module row (icon, name, description, badges, toggle).
struct ModuleRow: View {
    let entry: ModuleCatalogEntry
    let isEnabled: Bool
    let setEnabled: (Bool) -> Void

    private var d: ModuleDescriptor { entry.descriptor }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: d.iconSystemName).font(.system(size: 16)).frame(width: 26)
                .foregroundStyle(.primary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(d.displayName).font(.system(size: 13, weight: .semibold))
                    SourceBadge(source: entry.source)
                }
                Text(d.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Text("\(entry.source.label) · \(d.author) · v\(d.version)")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                Text(capabilityLine).font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { isEnabled }, set: setEnabled))
                .labelsHidden()
                .accessibilityLabel(Text("\(d.displayName), \(entry.source.label), \(isEnabled ? "enabled" : "disabled")"))
        }
        .padding(.vertical, 3)
    }

    private var capabilityLine: String {
        d.capabilities.isEmpty ? "No sensitive permissions"
            : d.capabilities.map(\.label).sorted().joined(separator: ", ")
    }
}

struct SourceBadge: View {
    let source: ModuleSource
    var body: some View {
        Text(source.label).font(.system(size: 8, weight: .bold))
            .padding(.horizontal, 5).padding(.vertical, 1.5)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel(Text("Source: \(source.label)"))
    }
    private var color: Color {
        switch source { case .builtIn: return .blue; case .community: return .orange; case .example: return .gray }
    }
}

/// Module detail sheet.
struct ModuleDetailSheet: View {
    let entry: ModuleCatalogEntry
    let isEnabled: Bool
    let setEnabled: (Bool) -> Void
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var d: ModuleDescriptor { entry.descriptor }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: d.iconSystemName).font(.system(size: 26)).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) { Text(d.displayName).font(.title3.bold()); SourceBadge(source: entry.source) }
                    Text("\(d.author) · v\(d.version)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("Enabled", isOn: Binding(get: { isEnabled }, set: setEnabled)).toggleStyle(.switch)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(d.summary).font(.callout)
                    labelledList("Surfaces", d.surfaces.map { $0.rawValue.capitalized }.sorted())
                    labelledList("Identifier", [d.identifier])
                    permissions
                    if d.identifier == SystemPulseModule.descriptor.identifier {
                        Divider()
                        Text("Settings").font(.headline)
                        SystemPulseSettingsView()
                    }
                    if d.identifier == AgentsModule.identifier {
                        Divider()
                        Text("Integration").font(.headline)
                        Text(AgentsModuleStrings.hookExplanation)
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(AgentsModuleStrings.manageIntegration) {
                            SettingsWindowPresenter.shared.show(section: .agents)
                        }.controlSize(.small)
                    }
                }
                .padding(16)
            }
            Divider()
            HStack {
                if entry.source == .community || entry.source == .example {
                    Button("Reset Module Settings", role: .destructive) { resetSettings() }.controlSize(.small)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(16)
        }
        .frame(width: 520, height: 480)
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Permissions").font(.headline)
            if d.capabilities.isEmpty {
                Text("No additional permissions required.").font(.callout)
                if entry.source == .community || entry.source == .example {
                    Text("Information is read locally and is not transmitted.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                ForEach(Array(d.capabilities).sorted(by: { $0.rawValue < $1.rawValue })) { c in
                    Label(c.label, systemImage: "lock.fill").font(.callout)
                }
            }
        }
    }

    private func labelledList(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            Text(items.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func resetSettings() {
        if d.identifier == SystemPulseModule.descriptor.identifier {
            settings.settings.systemPulse = .default
        }
    }
}
