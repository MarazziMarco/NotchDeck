import Foundation
import XCTest

/// Loads versioned JSONL fixtures from the test bundle.
///
/// The fixtures are declared as test resources. Loading them from the bundle
/// keeps the test runner independent from source-tree filesystem permissions.
enum FixtureLoader {
    static func lines(_ name: String) throws -> [String] {
        let resourceName = (name as NSString).deletingPathExtension
        let resourceExtension = (name as NSString).pathExtension
        let fixture = try XCTUnwrap(
            Bundle(for: FixtureBundleToken.self).url(
                forResource: resourceName,
                withExtension: resourceExtension.isEmpty ? nil : resourceExtension
            ),
            "Missing bundled fixture \(name)"
        )
        let content = try String(contentsOf: fixture, encoding: .utf8)
        return content.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

private final class FixtureBundleToken {}
