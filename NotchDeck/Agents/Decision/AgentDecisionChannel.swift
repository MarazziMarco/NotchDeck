import Foundation
import Security

// NotchDeck — VERIFIED decision channel for external responders (Arcus).
// Counterpart of Arcus' DecisionXPCClient. Arcus sends an AgentResolution over
// XPC; NotchDeck verifies the peer is the genuine Arcus binary (audit token →
// SecCodeCheckValidity against a pinned requirement) BEFORE honouring anything,
// then maps it onto the bridge's existing `respond(requestID:allow:)`.
//
// Security posture (matches the rest of Agents/):
//   • FAIL-CLOSED — an unverifiable peer, an undecodable frame, or an unknown /
//     expired request is refused; nothing is ever auto-approved on doubt.
//   • No env var / debug flag disables verification (spec + NotchDeck hardening).
//   • Peer identity comes from the audit token, NEVER from a recycled PID.
//
// Additive: this file introduces no dependency on existing runtime paths. Wiring
// it into AppEnvironment + registering the Mach service is the next step (N2).

// MARK: - Wire model (mirrors Arcus' ArcusCore schema, matched by JSON shape)

enum DecisionVerb: String, Codable { case accept, deny }

struct ResolutionScopeWire: Codable, Equatable {
    let type: String            // "once" | "always"
    let pattern: String?
}

struct AgentResolutionWire: Codable {
    let id: UUID
    let decision: DecisionVerb
    let scope: ResolutionScopeWire
}

enum AgentAckWire {
    case applied
    case rejected(reason: String)

    func encoded() -> Data {
        switch self {
        case .applied:
            return (try? JSONSerialization.data(withJSONObject: ["status": "applied"])) ?? Data()
        case .rejected(let reason):
            return (try? JSONSerialization.data(withJSONObject: ["status": "rejected", "reason": reason])) ?? Data()
        }
    }
}

/// The code-signing requirement NotchDeck pins to prove a decision came from the
/// genuine Arcus binary (spec §3). One shared source; both apps agree on it.
enum PeerRequirement {
    static let arcusIdentifier = "com.arcus.Arcus"

    /// Current local build: pin the self-signed "Arcus Dev" certificate leaf.
    static func selfSignedLeaf(sha1Hex: String, identifier: String = arcusIdentifier) -> String {
        "identifier \"\(identifier)\" and certificate leaf = H\"\(sha1Hex)\""
    }
    /// Future: Developer ID — pin the Team ID (survives cert rotation).
    static func developerID(teamID: String, identifier: String = arcusIdentifier) -> String {
        "identifier \"\(identifier)\" and anchor apple generic and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Arcus' current stable self-signed identity ("Arcus Dev").
    static let arcusSelfSigned = selfSignedLeaf(sha1Hex: "5928D3B4C9090553270E8B9C09D8ED1FD03FB1BC")
}

/// Pure translation of a verified resolution into a bridge decision — testable.
enum DecisionMapper {
    static func bridgeDecision(from res: AgentResolutionWire) -> (requestID: String, allow: Bool) {
        (requestID: res.id.uuidString, allow: res.decision == .accept)
    }
}

// MARK: - Peer verification (SecCode)

enum PeerCodeVerifier {
    /// Verify a live peer by its audit token against a requirement. FAIL-CLOSED:
    /// any failure to build the requirement, resolve the code, or validate → false.
    static func verify(auditToken: audit_token_t, requirement reqString: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(reqString as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        var token = auditToken
        let tokenData = Data(bytes: &token, count: MemoryLayout<audit_token_t>.size)
        let attrs: CFDictionary = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess,
              let code else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    /// Verify a signed bundle/binary on disk against a requirement (used by tests
    /// and diagnostics). FAIL-CLOSED on any error.
    static func verifyStatic(path: String, requirement reqString: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(reqString as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &staticCode) == errSecSuccess,
              let staticCode else { return false }
        return SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
    }
}

// MARK: - XPC service (listener + verified dispatch)

/// The remote interface Arcus calls. Selector must match Arcus' AgentDecisionXPC.
@objc protocol NotchAgentDecisionXPC {
    func resolve(_ resolution: Data, withReply reply: @escaping (Data?) -> Void)
}

/// The interface Arcus exports (notify). NotchDeck calls this to push a pending
/// request so Arcus opens its response menu. Selector matches Arcus' ArcusNotifyXPC.
@objc protocol ArcusNotifyXPC {
    func present(_ requestData: Data)
}

/// A pending request pushed to Arcus. Encodes to the exact JSON shape Arcus'
/// AgentRequest decodes (riskClass as its rawValue string).
struct AgentRequestWire: Codable {
    let id: UUID
    let agent: String
    let summary: String
    let detail: String
    let riskClass: String       // "low" | "medium" | "high"
    let expiresAtMs: Double
}

/// Vends the verified decision channel and dispatches accepted resolutions into
/// the bridge. `onResolve` returns whether the bridge actually applied it (a
/// missing / expired request returns false → the peer gets a rejected ack).
final class AgentDecisionService: NSObject, NSXPCListenerDelegate, NotchAgentDecisionXPC, @unchecked Sendable {
    static let machServiceName = "com.notchdeck.agentdecision"

    private let listener: NSXPCListener
    private let requirement: String
    private let onResolve: (_ requestID: String, _ allow: Bool) async -> Bool
    /// Verified peers to push notifications to. Guarded — mutated from the XPC
    /// delegate thread and read from notify().
    private let peersLock = NSLock()
    private var peers: [NSXPCConnection] = []

    /// Designated: run over any listener. A non-sandboxed GUI app cannot vend a
    /// global Mach name without launchd, so production uses an ANONYMOUS listener
    /// whose endpoint is published to a 0600 rendezvous file (see
    /// AgentDecisionRendezvous); the peer is still verified before anything runs.
    init(listener: NSXPCListener,
         requirement: String = PeerRequirement.arcusSelfSigned,
         onResolve: @escaping (_ requestID: String, _ allow: Bool) async -> Bool) {
        self.listener = listener
        self.requirement = requirement
        self.onResolve = onResolve
        super.init()
        listener.delegate = self
    }

    /// Anonymous listener — the production transport (no launchd needed).
    static func anonymous(requirement: String = PeerRequirement.arcusSelfSigned,
                          onResolve: @escaping (_ requestID: String, _ allow: Bool) async -> Bool)
        -> AgentDecisionService {
        AgentDecisionService(listener: NSXPCListener.anonymous(),
                             requirement: requirement, onResolve: onResolve)
    }

    var endpoint: NSXPCListenerEndpoint { listener.endpoint }

    func start() { listener.resume() }
    func stop() { listener.invalidate() }

    // MARK: NSXPCListenerDelegate — verify the peer BEFORE exporting anything.

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection conn: NSXPCConnection) -> Bool {
        guard let token = Self.auditToken(of: conn),
              PeerCodeVerifier.verify(auditToken: token, requirement: requirement) else {
            Log.agents.error("decision channel: peer refused (unverified)")
            return false                                   // fail-closed
        }
        conn.exportedInterface = NSXPCInterface(with: NotchAgentDecisionXPC.self)
        conn.exportedObject = self
        // We also CALL the peer (notify): push pending requests to Arcus.
        conn.remoteObjectInterface = NSXPCInterface(with: ArcusNotifyXPC.self)
        conn.invalidationHandler = { [weak self, weak conn] in self?.dropPeer(conn) }
        conn.interruptionHandler = { [weak self, weak conn] in self?.dropPeer(conn) }
        peersLock.lock(); peers.append(conn); peersLock.unlock()
        conn.resume()
        return true
    }

    private func dropPeer(_ conn: NSXPCConnection?) {
        guard let conn else { return }
        peersLock.lock(); peers.removeAll { $0 === conn }; peersLock.unlock()
    }

    /// Push a pending request to every verified Arcus peer (best-effort).
    func notify(_ request: AgentRequestWire) {
        guard let data = try? JSONEncoder().encode(request) else { return }
        peersLock.lock(); let targets = peers; peersLock.unlock()
        for conn in targets {
            (conn.remoteObjectProxy as? ArcusNotifyXPC)?.present(data)
        }
    }

    // MARK: NotchAgentDecisionXPC

    func resolve(_ resolution: Data, withReply reply: @escaping (Data?) -> Void) {
        guard let res = try? JSONDecoder().decode(AgentResolutionWire.self, from: resolution) else {
            reply(AgentAckWire.rejected(reason: "undecodable").encoded()); return
        }
        let (requestID, allow) = DecisionMapper.bridgeDecision(from: res)
        Task { [onResolve] in
            let applied = await onResolve(requestID, allow)
            let ack: AgentAckWire = applied ? .applied : .rejected(reason: "expired or unknown request")
            reply(ack.encoded())
        }
    }

    /// The peer's audit token — the only reliable identity input (never the PID).
    /// NotchDeck is non-sandboxed direct-download; reading the connection's audit
    /// token is acceptable here. Fail-closed if unavailable.
    private static func auditToken(of conn: NSXPCConnection) -> audit_token_t? {
        guard let value = conn.value(forKey: "auditToken") as? NSValue else { return nil }
        var token = audit_token_t()
        withUnsafeMutableBytes(of: &token) { raw in
            value.getValue(raw.baseAddress!, size: MemoryLayout<audit_token_t>.size)
        }
        return token
    }
}

// MARK: - Rendezvous (endpoint hand-off without launchd)

/// NotchDeck publishes its anonymous listener endpoint to a 0600 file that only
/// the same user can read; Arcus reads it and connects. A forged endpoint only
/// lets a caller *attempt* a connection — it is still peer-verified before any
/// decision is honoured, so the file's confidentiality is defence in depth, not
/// the trust boundary.
enum AgentDecisionRendezvous {
    /// Shared, user-only location (same 0700 dir the bridge already owns).
    static func endpointURL() -> URL {
        TerminalAgentProtocol.socketURL()
            .deletingLastPathComponent()
            .appendingPathComponent("agent-decision.endpoint")
    }

    @discardableResult
    static func publish(_ endpoint: NSXPCListenerEndpoint) -> Bool {
        let url = endpointURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700])
            let data = try NSKeyedArchiver.archivedData(withRootObject: endpoint,
                                                        requiringSecureCoding: true)
            try data.write(to: url, options: [.atomic])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            Log.agents.error("decision rendezvous publish failed: \(error.localizedDescription)")
            return false
        }
    }

    static func read() -> NSXPCListenerEndpoint? {
        guard let data = try? Data(contentsOf: endpointURL()) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSXPCListenerEndpoint.self, from: data)
    }

    static func clear() { try? FileManager.default.removeItem(at: endpointURL()) }
}
