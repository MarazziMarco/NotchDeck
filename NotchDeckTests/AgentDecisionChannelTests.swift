import XCTest
import Security
@testable import NotchDeck

/// The verified decision channel (Arcus → NotchDeck). Covers the pure, security-
/// critical logic: wire decoding, decision mapping, the pinned peer requirement,
/// and that peer verification FAILS CLOSED on an unsatisfiable requirement.
final class AgentDecisionChannelTests: XCTestCase {

    func testResolutionDecodesFromArcusJSON() throws {
        // Exactly the shape Arcus' AgentResolution encodes.
        let json = """
        {"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8",
         "decision":"accept",
         "scope":{"type":"always","pattern":"git commit -m *"}}
        """.data(using: .utf8)!
        let res = try JSONDecoder().decode(AgentResolutionWire.self, from: json)
        XCTAssertEqual(res.decision, .accept)
        XCTAssertEqual(res.scope.type, "always")
        XCTAssertEqual(res.scope.pattern, "git commit -m *")
    }

    func testDecisionMapping() throws {
        let json = #"{"id":"6BA7B810-9DAD-11D1-80B4-00C04FD430C8","decision":"deny","scope":{"type":"once"}}"#
            .data(using: .utf8)!
        let res = try JSONDecoder().decode(AgentResolutionWire.self, from: json)
        let d = DecisionMapper.bridgeDecision(from: res)
        XCTAssertEqual(d.requestID, "6BA7B810-9DAD-11D1-80B4-00C04FD430C8")
        XCTAssertFalse(d.allow)                       // deny → allow == false
    }

    func testAckEncoding() throws {
        let applied = try JSONSerialization.jsonObject(with: AgentAckWire.applied.encoded()) as? [String: String]
        XCTAssertEqual(applied?["status"], "applied")
        let rejected = try JSONSerialization.jsonObject(with: AgentAckWire.rejected(reason: "expired").encoded()) as? [String: String]
        XCTAssertEqual(rejected?["status"], "rejected")
        XCTAssertEqual(rejected?["reason"], "expired")
    }

    func testPeerRequirementStrings() {
        XCTAssertEqual(
            PeerRequirement.arcusSelfSigned,
            "identifier \"com.arcus.Arcus\" and certificate leaf = H\"5928D3B4C9090553270E8B9C09D8ED1FD03FB1BC\"")
        XCTAssertEqual(
            PeerRequirement.developerID(teamID: "ABCDE12345"),
            "identifier \"com.arcus.Arcus\" and anchor apple generic and certificate leaf[subject.OU] = \"ABCDE12345\"")
    }

    /// Fail-closed: verifying THIS test binary against a requirement it cannot
    /// satisfy (Arcus' identifier/leaf) must return false — never a permissive pass.
    func testPeerVerifyFailsClosedOnForeignRequirement() {
        let path = Bundle.main.bundlePath
        XCTAssertFalse(PeerCodeVerifier.verifyStatic(path: path, requirement: PeerRequirement.arcusSelfSigned))
        // A malformed requirement string must also fail closed, not throw/pass.
        XCTAssertFalse(PeerCodeVerifier.verifyStatic(path: path, requirement: "this is not a requirement"))
    }

    /// End-to-end over a real anonymous XPC endpoint: a VERIFIED peer's resolution
    /// is decoded and dispatched to the onResolve callback with the right values.
    /// The requirement is this process's OWN designated requirement so the
    /// in-process loopback peer verifies — a test seam, not a production bypass
    /// (production pins the Arcus requirement, which no other process can satisfy).
    func testVerifiedResolveDispatches() throws {
        let selfReq = try XCTUnwrap(ownDesignatedRequirement(), "need self requirement")
        let dispatched = expectation(description: "onResolve called")
        let box = ResultBox()
        let service = AgentDecisionService.anonymous(requirement: selfReq) { requestID, allow in
            box.set(requestID: requestID, allow: allow)
            dispatched.fulfill()
            return true
        }
        service.start()
        defer { service.stop() }

        let conn = NSXPCConnection(listenerEndpoint: service.endpoint)
        conn.remoteObjectInterface = NSXPCInterface(with: NotchAgentDecisionXPC.self)
        conn.resume()
        defer { conn.invalidate() }
        let proxy = try XCTUnwrap(conn.remoteObjectProxy as? NotchAgentDecisionXPC)

        let id = UUID()
        let json = #"{"id":"\#(id.uuidString)","decision":"accept","scope":{"type":"once"}}"#
            .data(using: .utf8)!
        let acked = expectation(description: "ack received")
        proxy.resolve(json) { replyData in
            let obj = replyData.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: String] }
            XCTAssertEqual(obj?["status"], "applied")     // onResolve returned true → applied
            acked.fulfill()
        }
        wait(for: [dispatched, acked], timeout: 5)
        XCTAssertEqual(box.requestID, id.uuidString)
        XCTAssertEqual(box.allow, true)
    }

    func testRequestWireMatchesArcusShape() throws {
        let id = UUID()
        let req = AgentRequestWire(id: id, agent: "Claude Code", summary: "Run tests",
                                   detail: "swift test", riskClass: "medium", expiresAtMs: 123456)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
        XCTAssertEqual(obj?["id"] as? String, id.uuidString)      // uppercase, matches Arcus
        XCTAssertEqual(obj?["agent"] as? String, "Claude Code")
        XCTAssertEqual(obj?["riskClass"] as? String, "medium")
        XCTAssertEqual(obj?["expiresAtMs"] as? Double, 123456)
        XCTAssertNotNil(obj?["summary"]); XCTAssertNotNil(obj?["detail"])
    }

    // MARK: helpers

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private(set) var requestID: String?
        private(set) var allow: Bool?
        func set(requestID: String, allow: Bool) {
            lock.lock(); defer { lock.unlock() }
            self.requestID = requestID; self.allow = allow
        }
    }

    private func ownDesignatedRequirement() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var req: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticCode, [], &req) == errSecSuccess, let req else { return nil }
        var str: CFString?
        guard SecRequirementCopyString(req, [], &str) == errSecSuccess, let str else { return nil }
        return str as String
    }
}
