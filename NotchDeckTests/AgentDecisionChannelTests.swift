import XCTest
import Security
@testable import NotchDeck

/// The verified decision channel (Arcus → NotchDeck). Covers the pure, security-
/// critical logic: wire decoding, decision mapping, the pinned peer requirement,
/// the request-push shape, and that peer verification FAILS CLOSED.
final class AgentDecisionChannelTests: XCTestCase {

    func testResolutionDecodesFromArcusJSON() throws {
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

    func testRequestWireMatchesArcusShape() throws {
        let id = UUID()
        let req = AgentRequestWire(id: id, agent: "Claude Code", summary: "Run tests",
                                   detail: "swift test", riskClass: "medium", expiresAtMs: 123456)
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(req)) as? [String: Any]
        XCTAssertEqual(obj?["id"] as? String, id.uuidString)      // uppercase, matches Arcus
        XCTAssertEqual(obj?["agent"] as? String, "Claude Code")
        XCTAssertEqual(obj?["riskClass"] as? String, "medium")
        XCTAssertEqual(obj?["expiresAtMs"] as? Double, 123456)
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
        XCTAssertFalse(PeerCodeVerifier.verifyStatic(path: path, requirement: "this is not a requirement"))
    }
}
