import Foundation

/// Parses a single line of `codex exec --json` output into normalized events.
/// Tolerant by design: unknown lines, non-JSON stderr and schema drift degrade
/// to `.log` rather than throwing. Based on the thread/turn/item envelope
/// emitted by codex-cli 0.144.x.
enum CodexEventParser {

    /// Parse one line. Returns zero or more normalized events.
    static func parse(line: String) -> [AgentEvent] {
        guard let data = line.data(using: .utf8),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            // Non-JSON line (e.g. stray stderr): surface as a log entry only.
            return [.log(line)]
        }
        guard let type = obj["type"] as? String else { return [.log(line)] }

        switch type {
        case "thread.started":
            let threadID = obj["thread_id"] as? String
            return [.started(providerSessionID: threadID)]

        case "turn.started":
            return [.status(.running)]

        case "turn.completed":
            let summary = (obj["usage"] as? [String: Any]).map { _ in "" }
            return [.completed(summary: summary?.isEmpty == true ? nil : summary)]

        case "turn.failed":
            let message = ((obj["error"] as? [String: Any])?["message"] as? String) ?? "Turn failed"
            return [.failed(reason: message)]

        case "error":
            let message = (obj["message"] as? String) ?? "Codex error"
            return [.failed(reason: message)]

        case "item.started", "item.updated", "item.completed":
            return parseItem(obj["item"] as? [String: Any], envelopeType: type)

        default:
            return [.log(line)]
        }
    }

    private static func parseItem(_ item: [String: Any]?, envelopeType: String) -> [AgentEvent] {
        guard let item, let itemType = item["type"] as? String else { return [] }
        let completed = envelopeType == "item.completed"

        switch itemType {
        case "agent_message", "assistant_message", "message":
            let text = (item["text"] as? String)
                ?? (item["message"] as? String)
                ?? textFromContent(item["content"])
            guard let text, !text.isEmpty else { return [] }
            return completed ? [.message(role: "assistant", text: text)] : []

        case "reasoning":
            let text = (item["text"] as? String) ?? (item["summary"] as? String) ?? ""
            return text.isEmpty ? [] : [.log("reasoning: \(text)")]

        case "command_execution", "tool_call", "local_shell_call", "function_call":
            let name = (item["name"] as? String)
                ?? (item["command"] as? String)
                ?? "command"
            let summary = (item["command"] as? String)
                ?? (item["arguments"] as? String)
                ?? name
            return [.toolUse(name: name, summary: summary)]

        case "approval_request", "exec_approval_request", "apply_patch_approval_request":
            let summary = (item["command"] as? String)
                ?? (item["message"] as? String)
                ?? "Approval required"
            return [.approvalRequested(summary: summary)]

        case "error":
            let message = (item["message"] as? String) ?? "Codex item error"
            return [.log("error: \(message)")]

        default:
            return []
        }
    }

    /// Extract concatenated text from an OpenAI-style content array.
    private static func textFromContent(_ raw: Any?) -> String? {
        guard let array = raw as? [[String: Any]] else { return nil }
        let parts = array.compactMap { $0["text"] as? String }
        return parts.isEmpty ? nil : parts.joined()
    }
}
