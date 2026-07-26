import Foundation
import XCTest

/// Loads versioned JSONL fixtures from the repo (located relative to this file
/// so tests don't depend on bundle resource wiring).
enum FixtureLoader {
    static func lines(_ name: String) throws -> [String] {
        let thisFile = URL(fileURLWithPath: #filePath)
        let fixture = thisFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name)")
        let content = try String(contentsOf: fixture, encoding: .utf8)
        return content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}
