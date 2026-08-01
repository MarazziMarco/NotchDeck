import Foundation
import Darwin
import Security

// NotchDeck — VERIFIED decision channel for external responders (Arcus).
//
// Transport: a dedicated Unix-domain socket (0600) — NOT XPC. App-to-app XPC
// needs a launchd-registered Mach name, and NSXPCListenerEndpoint cannot be
// serialised to hand off ("may only be encoded by an NSXPCCoder"), so the socket
// (spec §2 option 2) is the working, launchd-free path and reuses the bridge's
// hardened socket bootstrap. The peer is verified via its audit token
// (getsockopt LOCAL_PEERTOKEN → SecCodeCheckValidity against a pinned
// requirement) at connect, BEFORE any frame is honoured.
//
// Security posture (matches the rest of Agents/):
//   • FAIL-CLOSED — an unverifiable peer / undecodable frame / unknown request is
//     refused; nothing is auto-approved on doubt.
//   • No env var / debug flag disables verification.
//   • Peer identity from the audit token, NEVER a recycled PID.
//
// Framing: JSONL. { "type":"resolve", "payload": <AgentResolution> } in;
//                 { "type":"ack", "id":…, "status":… } and
//                 { "type":"notify", "payload": <AgentRequest> } out.

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

/// The code-signing requirement NotchDeck pins to prove a decision came from the
/// genuine Arcus binary (spec §3). One shared source; both apps agree on it.
enum PeerRequirement {
    static let arcusIdentifier = "com.arcus.Arcus"

    static func selfSignedLeaf(sha1Hex: String, identifier: String = arcusIdentifier) -> String {
        "identifier \"\(identifier)\" and certificate leaf = H\"\(sha1Hex)\""
    }
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
    /// Verify a peer by its audit token against a requirement. FAIL-CLOSED.
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

    /// Verify a signed bundle/binary on disk (tests / diagnostics). FAIL-CLOSED.
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

// MARK: - Socket path

enum AgentDecisionSocketPath {
    /// Same user-only 0700 dir the bridge already owns.
    static func url() -> URL {
        TerminalAgentProtocol.socketURL()
            .deletingLastPathComponent()
            .appendingPathComponent("agent-decision.sock")
    }
}

// getsockopt(SOL_LOCAL, LOCAL_PEERTOKEN) → the peer's audit_token_t (from <sys/un.h>).
private let kSOL_LOCAL: Int32 = 0
private let kLOCAL_PEERTOKEN: Int32 = 0x006

// MARK: - Socket server (verified, bidirectional)

final class AgentDecisionSocket: @unchecked Sendable {
    private let requirement: String
    private let onResolve: (_ requestID: String, _ allow: Bool) async -> Bool

    private let stateLock = NSLock()
    private var running = false
    private var lease: BridgeSocketLease?
    private var listenFD: Int32 = -1

    private let peersLock = NSLock()
    private var peers = Set<Int32>()            // verified client fds
    private let writeLock = NSLock()            // serialise frame writes

    init(requirement: String = PeerRequirement.arcusSelfSigned,
         onResolve: @escaping (_ requestID: String, _ allow: Bool) async -> Bool) {
        self.requirement = requirement
        self.onResolve = onResolve
    }

    func start() {
        stateLock.lock(); defer { stateLock.unlock() }
        guard !running else { return }
        let path = AgentDecisionSocketPath.url().path
        do {
            let lease = try BridgeSocketBootstrap.bind(path: path)
            self.lease = lease
            self.listenFD = lease.fileDescriptor
        } catch {
            Log.agents.error("decision socket bind failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        running = true
        let fd = listenFD
        let t = Thread { [weak self] in self?.acceptLoop(fd: fd) }
        t.name = "notchdeck.decision.accept"; t.start()
    }

    func stop() {
        stateLock.lock(); running = false; let l = lease; lease = nil; stateLock.unlock()
        l?.closeAndUnlink()
        peersLock.lock(); let fds = peers; peers.removeAll(); peersLock.unlock()
        for fd in fds { close(fd) }
    }

    private var isRunning: Bool { stateLock.lock(); defer { stateLock.unlock() }; return running }

    // MARK: accept / verify / read

    private func acceptLoop(fd: Int32) {
        while isRunning {
            let client = accept(fd, nil, nil)
            if client < 0 { if !isRunning { break }; continue }
            var noSignal: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, socklen_t(MemoryLayout<Int32>.size))
            guard verifyPeer(fd: client) else {
                Log.agents.error("decision socket: peer refused (unverified)")
                close(client); continue                       // fail-closed
            }
            peersLock.lock(); peers.insert(client); peersLock.unlock()
            let rt = Thread { [weak self] in self?.readLoop(client) }
            rt.name = "notchdeck.decision.read"; rt.start()
        }
    }

    private func verifyPeer(fd: Int32) -> Bool {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        let rc = withUnsafeMutablePointer(to: &token) { ptr -> Int32 in
            getsockopt(fd, kSOL_LOCAL, kLOCAL_PEERTOKEN, UnsafeMutableRawPointer(ptr), &len)
        }
        guard rc == 0, len == socklen_t(MemoryLayout<audit_token_t>.size) else { return false }
        return PeerCodeVerifier.verify(auditToken: token, requirement: requirement)
    }

    private func readLoop(_ fd: Int32) {
        var buffer = [UInt8](repeating: 0, count: 4096)
        var pending = Data()
        while isRunning {
            let n = read(fd, &buffer, buffer.count)
            if n <= 0 { break }
            pending.append(contentsOf: buffer[0..<n])
            while let nl = pending.firstIndex(of: 0x0A) {
                let line = pending.subdata(in: pending.startIndex..<nl)
                pending.removeSubrange(pending.startIndex...nl)
                handleFrame(line, fd: fd)
            }
        }
        peersLock.lock(); peers.remove(fd); peersLock.unlock()
        close(fd)
    }

    private func handleFrame(_ data: Data, fd: Int32) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "resolve",
              let payload = obj["payload"],
              let pd = try? JSONSerialization.data(withJSONObject: payload),
              let res = try? JSONDecoder().decode(AgentResolutionWire.self, from: pd) else { return }
        let (requestID, allow) = DecisionMapper.bridgeDecision(from: res)
        Task { [weak self] in
            let applied = await self?.onResolve(requestID, allow) ?? false
            self?.writeFrame(["type": "ack", "id": res.id.uuidString,
                              "status": applied ? "applied" : "rejected"], to: fd)
        }
    }

    /// Push a pending request to every verified peer (best-effort).
    func notify(_ request: AgentRequestWire) {
        guard let pd = try? JSONEncoder().encode(request),
              let payload = try? JSONSerialization.jsonObject(with: pd) else { return }
        peersLock.lock(); let targets = peers; peersLock.unlock()
        for fd in targets { writeFrame(["type": "notify", "payload": payload], to: fd) }
    }

    private func writeFrame(_ obj: [String: Any], to fd: Int32) {
        guard var data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        data.append(0x0A)
        writeLock.lock(); defer { writeLock.unlock() }
        data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < data.count {
                let w = write(fd, base.advanced(by: offset), data.count - offset)
                if w > 0 { offset += w }
                else if w < 0 && errno == EINTR { continue }
                else { break }
            }
        }
    }
}
