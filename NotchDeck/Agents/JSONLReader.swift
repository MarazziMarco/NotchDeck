import Foundation

/// Incremental newline-delimited buffer. Feed arbitrary byte chunks from a pipe
/// and get back complete lines; partial trailing data is retained until the
/// next feed. Non-JSON lines (e.g. stray stderr) are returned as-is for the
/// caller to decide what to do.
struct LineBuffer {
    private var pending = Data()

    /// Append new bytes and return any newly completed lines (without newline).
    mutating func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        while let range = pending.firstRange(of: Data([0x0A])) {
            let lineData = pending.subdata(in: pending.startIndex..<range.lowerBound)
            pending.removeSubrange(pending.startIndex..<range.upperBound)
            if let line = String(data: lineData, encoding: .utf8) {
                let trimmed = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
                if !trimmed.isEmpty { lines.append(trimmed) }
            }
        }
        return lines
    }

    /// Flush any remaining buffered content as a final line.
    mutating func flush() -> String? {
        guard !pending.isEmpty else { return nil }
        let line = String(data: pending, encoding: .utf8)
        pending.removeAll()
        let trimmed = line?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == false) ? trimmed : nil
    }
}
