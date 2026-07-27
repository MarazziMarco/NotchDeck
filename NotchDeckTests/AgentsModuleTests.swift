import XCTest
@testable import NotchDeck

/// Agents-as-a-module: catalogue presence, enablement, root-workspace behaviour,
/// compact suppression and settings preservation.
final class AgentsModuleTests: XCTestCase {

    // MARK: Catalogue / classification (items 1–2, 8–9; clarification 1–2, 8–9)

    private func catalog(agentsEnabled: Bool = true) -> ModuleCatalog {
        ModuleCatalog(
            builtIn: [
                LegacyModuleAdapter.descriptor(id: "quickNote", name: "Quick Note",
                    icon: "note.text", defaultEnabled: true, hasSettings: false),
                AgentsModule.descriptor,
            ],
            community: [], example: [], includeExample: false)
    }

    func testAgentsAppearsInCatalogue() {
        XCTAssertNotNil(catalog().entry(id: AgentsModule.identifier))
    }

    func testAgentsClassifiedBuiltIn() {
        XCTAssertEqual(catalog().entry(id: AgentsModule.identifier)?.source, .builtIn)
    }

    func testAgentsEnabledByDefaultDescriptor() {
        XCTAssertTrue(AgentsModule.descriptor.defaultEnabled)
        XCTAssertTrue(AgentsModule.isEnabled(AppSettings()))
    }

    func testAgentsDescriptorMetadata() {
        let d = AgentsModule.descriptor
        XCTAssertEqual(d.identifier, "built-in.agents")
        XCTAssertEqual(d.displayName, "Agents")
        XCTAssertEqual(d.author, "NotchDeck")
        XCTAssertEqual(d.version, "1.0.0")
        XCTAssertEqual(d.capabilities,
                       [.terminalSessionEvents, .agentApprovalEvents, .terminalAutomation])
        XCTAssertTrue(d.surfaces.contains(.workspace))
    }

    func testAgentsIsWorkspaceNotHomeCard() {
        let entry = catalog().entry(id: AgentsModule.identifier)!
        XCTAssertFalse(entry.isHomeModule, "Agents must never be a Home card")
        XCTAssertFalse(entry.descriptor.surfaces.contains(.homeCard))
    }

    func testAgentsNeverInUtilityNavigation() {
        // The utility tabs are exactly Home/Focus/Files/More — Agents is not one.
        XCTAssertEqual(UtilitiesTab.allCases.map(\.rawValue), ["home", "focus", "files", "more"])
        XCTAssertFalse(UtilitiesTab.allCases.contains { $0.rawValue == "agents" })
    }

    func testAgentsNotAddedToHomeOrderWhenToggled() {
        var s = AppSettings()
        s.editorialOrder = ["quickNote", "mirror"]
        ModuleEnablement.setEnabled(AgentsModule.identifier, true, isHomeModule: false,
                                    defaultOrder: EditorialHomeLayout.defaultOrder, in: &s)
        XCTAssertEqual(s.editorialOrder, ["quickNote", "mirror"], "workspace is not reorderable with Home")
    }

    // MARK: Enablement persistence (items 3–5)

    func testDisableEnablePersistsInModuleEnabled() {
        var s = AppSettings()
        ModuleEnablement.setEnabled(AgentsModule.identifier, false, isHomeModule: false,
                                    defaultOrder: [], in: &s)
        XCTAssertEqual(s.moduleEnabled[AgentsModule.identifier], false)
        XCTAssertFalse(AgentsModule.isEnabled(s))
        ModuleEnablement.setEnabled(AgentsModule.identifier, true, isHomeModule: false,
                                    defaultOrder: [], in: &s)
        XCTAssertTrue(AgentsModule.isEnabled(s))
    }

    func testDisableDoesNotUninstallHooksOrTouchIntegration() {
        var s = AppSettings()
        s.codexTerminalIntegration = true
        s.claudeTerminalIntegration = true
        s.agentPermissionMode = .prompt
        ModuleEnablement.setEnabled(AgentsModule.identifier, false, isHomeModule: false,
                                    defaultOrder: [], in: &s)
        XCTAssertTrue(s.codexTerminalIntegration, "installed hooks/integration untouched")
        XCTAssertTrue(s.claudeTerminalIntegration)
        XCTAssertEqual(s.agentPermissionMode, .prompt, "permission mode preserved")
    }

    func testToggleDoesNotAffectOtherModules() {
        var s = AppSettings()
        s.moduleEnabled["community.system-pulse"] = true
        ModuleEnablement.setEnabled(AgentsModule.identifier, false, isHomeModule: false,
                                    defaultOrder: [], in: &s)
        XCTAssertEqual(s.moduleEnabled["community.system-pulse"], true, "System Pulse unaffected")
    }

    // MARK: Root workspace state (items 9–11; clarification 2, 5–7)

    @MainActor func testDefaultsToUtilitiesWhenAgentsDisabled() {
        var settings = AppSettings()
        settings.defaultFace = .agents
        settings.moduleEnabled[AgentsModule.identifier] = false
        let app = AppState(settings: SettingsStore.inMemory(settings))
        XCTAssertEqual(app.face, .utilities, "persisted .agents normalised when disabled")
        XCTAssertFalse(app.agentsEnabled)
    }

    @MainActor func testDisablingWhileOnAgentsSwitchesToUtilities() {
        var settings = AppSettings()
        settings.defaultFace = .agents
        let store = SettingsStore.inMemory(settings)
        let app = AppState(settings: store)
        XCTAssertEqual(app.face, .agents)
        store.settings.moduleEnabled[AgentsModule.identifier] = false
        XCTAssertEqual(app.face, .utilities)
        XCTAssertFalse(app.agentsEnabled)
    }

    @MainActor func testReEnablingDoesNotSwitchToAgents() {
        let store = SettingsStore.inMemory(AppSettings())
        let app = AppState(settings: store)
        store.settings.moduleEnabled[AgentsModule.identifier] = false
        XCTAssertEqual(app.face, .utilities)
        store.settings.moduleEnabled[AgentsModule.identifier] = true
        XCTAssertTrue(app.agentsEnabled)
        XCTAssertEqual(app.face, .utilities, "re-enabling never auto-selects Agents")
    }

    @MainActor func testToggleFaceToAgentsBlockedWhileDisabled() {
        var settings = AppSettings()
        settings.moduleEnabled[AgentsModule.identifier] = false
        let app = AppState(settings: SettingsStore.inMemory(settings))
        app.toggleFace(to: .agents)
        XCTAssertEqual(app.face, .utilities, "Agents unreachable while disabled")
    }

    @MainActor func testAgentsEnabledFlagTracksSettings() {
        let store = SettingsStore.inMemory(AppSettings())
        let app = AppState(settings: store)
        XCTAssertTrue(app.agentsEnabled)
        store.settings.moduleEnabled[AgentsModule.identifier] = false
        XCTAssertFalse(app.agentsEnabled)
    }

    // MARK: Compact suppression (item 8, 12)

    @MainActor func testCompactActivitySuppressedWhenDisabled() {
        let store = AgentSessionStore(fileName: "test-agents-\(UUID().uuidString).json")
        store.upsert(AgentSession(provider: .claudeCode, title: "proj",
                                  projectPath: "/tmp/proj", status: .running, isManaged: true))
        XCTAssertNotNil(store.currentActivity(), "running session yields compact activity")
        store.compactSuppressed = true
        XCTAssertNil(store.currentActivity(), "disabled Agents contributes no compact activity")
    }

    @MainActor func testHistorySurvivesSuppression() {
        let store = AgentSessionStore(fileName: "test-agents-\(UUID().uuidString).json")
        store.upsert(AgentSession(provider: .codex, title: "p", projectPath: "/tmp",
                                  status: .completed, isManaged: true))
        store.compactSuppressed = true
        XCTAssertEqual(store.sessions.count, 1, "session history preserved while suppressed")
    }

    // MARK: Approval safety (items 23–24) — never auto-approve on a request

    func testPermissionRequestNeverAutoApproves() {
        let event = TerminalAgentEvent(type: .toolPermissionRequested, provider: .claudeCode,
                                       sessionID: "s1", timestamp: 0, requestID: "r1")
        let s = TerminalAgentBridge.reduce(existing: nil, id: UUID(), event: event)
        XCTAssertEqual(s.status, .waitingForApproval)
        XCTAssertNotEqual(s.latestSummary, "Approved", "a request is never silently approved")
    }

    // MARK: Structure invariants

    func testNotchFaceHasTwoWorkspaces() {
        XCTAssertEqual(Set(NotchFace.allCases), [.utilities, .agents])
    }
}
