import SwiftUI

/// The More Module Library: browse and add/remove modules for the Utilities →
/// More dashboard ONLY. Two sections — Built-in and Community — derived from the
/// authoritative registries. It never customizes Home.
struct MoreModuleLibraryView: View {
    let moduleViews: [MoreModuleView]
    @EnvironmentObject private var registry: ModuleRegistry
    @EnvironmentObject private var community: CommunityModuleRegistry
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private var definitions: [MoreModuleDescriptor] { moduleViews.map(\.descriptor) }
    private func placed(_ d: MoreModuleDescriptor) -> Bool { MoreCatalog.isPlaced(d, settings: settings.settings) }

    private var builtIns: [MoreModuleDescriptor] { definitions.filter { $0.source == .builtIn } }
    private var communityMods: [MoreModuleDescriptor] { definitions.filter { $0.source == .community || $0.source == .example } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("More Module Library").font(.title3.bold())
                    Text("Add modules to the More dashboard. This does not affect Home.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Built-in", builtIns)
                    section("Community", communityMods)
                }
                .padding(16)
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ mods: [MoreModuleDescriptor]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            if mods.isEmpty {
                Text("No \(title.lowercased()) modules available.")
                    .font(.caption).foregroundStyle(.tertiary)
            } else {
                ForEach(mods) { row($0) }
            }
        }
    }

    private func row(_ d: MoreModuleDescriptor) -> some View {
        let isAdded = placed(d)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: d.iconSystemName).font(.system(size: 16)).frame(width: 26)
                .foregroundStyle(.primary).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(d.name).font(.system(size: 13, weight: .semibold))
                if !d.summary.isEmpty {
                    Text(d.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                Text("\(d.source.label) · sizes: \(d.supportedSizes.map(\.label).joined(separator: ", "))")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(isAdded ? "Remove" : "Add") { toggle(d, add: !isAdded) }
                .controlSize(.small)
                .accessibilityLabel(Text("\(isAdded ? "Remove" : "Add") \(d.name) \(isAdded ? "from" : "to") More"))
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(isAdded ? "Added" : "Not added"))
    }

    private func toggle(_ d: MoreModuleDescriptor, add: Bool) {
        settings.updateMoreLayout(definitions: definitions) {
            $0.moduleEnabled[d.id] = add
        }
    }
}
