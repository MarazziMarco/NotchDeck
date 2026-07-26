import Foundation

/// Parses a single line of Claude Code `--output-format stream-json` output into
/// normalized events. Tolerant: unknown types degrade to `.log`. Based on the
/// Claude Code 2.1.x stream-json schema (system/init, assistant, result…).
enum ClaudeEventParser {

    static func parse(line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return [.log(line)]
        }
        guard let type = obj["type"] as? String else { return [.log(line)] }

        switch type {
        case "system":
            let subtype = obj["subtype"] as? String
            if subtype == "init" {
                let sessionID = obj["session_id"] as? String
                return [.started(providerSessionID: sessionID), .status(.running)]
            }
            return []   // hooks, thinking_tokens, etc. are noise for the UI

        case "assistant":
            return parseAssistant(obj["message"] as? [String: Any])

        case "user":
            // Tool results returning to the model; not user-facing.
            return []

        case "control_request", "can_use_tool", "permission_request":
            let summary = (obj["tool_name"] as? String)
                ?? (obj["message"] as? String)
                ?? "Approval required"
            return [.approvalRequested(summary: summary)]

        case "result":
            let isError = (obj["is_error"] as? Bool) ?? false
            let text = obj["result"] as? String
            if isError {
                return [.failed(reason: text ?? "Session failed")]
            }
            return [.completed(summary: text)]

        case "rate_limit_event":
            return [.log("rate limit event")]

        default:
            return [.log(line)]
        }
    }

    private static func parseAssistant(_ message: [String: Any]?) -> [AgentEvent] {
        guard let content = message?["content"] as? [[String: Any]] else { return [] }
        var events: [AgentEvent] = []
        for block in content {
            guard let blockType = block["type"] as? String else { continue }
            switch blockType {
            case "text":
                if let text = block["text"] as? String, !text.isEmpty {
                    events.append(.message(role: "assistant", text: text))
                }
            case "thinking":
                if let text = block["thinking"] as? String, !text.isEmpty {
                    events.append(.log("thinking: \(text)"))
                }
            case "tool_use":
                let name = (block["name"] as? String) ?? "tool"
                let input = block["input"].map { "\($0)" } ?? ""
                events.append(.toolUse(name: name, summary: input))
            default:
                break
            }
        }
        return events
    }
}
