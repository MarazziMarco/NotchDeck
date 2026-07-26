import Foundation

/// Size-bounded, sanitized, append-only log for agent sessions. Old content is
/// dropped once the cap is exceeded — we never keep full stdout forever.
final class RotatingLog {
    private let url: URL
    private let maxBytes: Int
    private let queue = DispatchQueue(label: "com.notchdeck.agentlog")
    private var enabled: Bool

    init(sessionID: UUID, maxBytes: Int, enabled: Bool) {
        self.url = AppPaths.logsDirectory.appendingPathComponent("agent-\(sessionID.uuidString).log")
        self.maxBytes = maxBytes
        self.enabled = enabled
    }

    func setEnabled(_ value: Bool) { queue.async { self.enabled = value } }

    func append(_ line: String) {
        queue.async {
            guard self.enabled else { return }
            let sanitized = SecretSanitizer.redact(line) + "\n"
            guard let data = sanitized.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: self.url) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            } else {
                try? sanitized.write(to: self.url, atomically: true, encoding: .utf8)
            }
            self.rotateIfNeeded()
        }
    }

    private func rotateIfNeeded() {
        guard let size = try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int,
              size > maxBytes else { return }
        // Keep the trailing half of the file.
        guard let data = try? Data(contentsOf: url) else { return }
        let keep = data.suffix(maxBytes / 2)
        try? keep.write(to: url, options: [.atomic])
    }

    func readAll() -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    func delete() { try? FileManager.default.removeItem(at: url) }
}
