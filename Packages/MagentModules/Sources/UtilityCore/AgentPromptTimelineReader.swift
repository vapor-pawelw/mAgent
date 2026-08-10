import Foundation
import MagentModels

public enum AgentPromptTimelineReader {
    public static func timings(
        agentType: AgentType,
        sessionID: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [SubmittedPromptTiming] {
        guard let url = sessionURL(agentType: agentType, sessionID: sessionID, homeDirectory: homeDirectory),
              let jsonl = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return timings(agentType: agentType, jsonl: jsonl)
    }

    public static func timings(agentType: AgentType, jsonl: String) -> [SubmittedPromptTiming] {
        var result: [SubmittedPromptTiming] = []
        var unfinishedIndexes: [Int] = []

        for rawLine in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(rawLine).data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let timestamp = date(from: object["timestamp"]) else {
                continue
            }

            if let prompt = promptText(agentType: agentType, object: object) {
                result.append(SubmittedPromptTiming(text: prompt, sentAt: timestamp))
                unfinishedIndexes.append(result.count - 1)
                continue
            }

            guard isCompletion(agentType: agentType, object: object) else { continue }
            for index in unfinishedIndexes where result[index].sentAt <= timestamp {
                result[index].completedAt = timestamp
            }
            unfinishedIndexes.removeAll { result[$0].completedAt != nil }
        }
        return result
    }

    public static func reconcile(
        local: [SubmittedPromptTiming],
        authoritative: [SubmittedPromptTiming]
    ) -> [SubmittedPromptTiming] {
        guard !authoritative.isEmpty else { return local }
        var merged = local
        var nextLocalIndex = merged.endIndex

        for timing in authoritative.reversed() {
            let normalizedText = normalized(timing.text)
            if let index = merged.indices[..<nextLocalIndex].last(where: {
                normalized(merged[$0].text) == normalizedText
            }) {
                merged[index] = SubmittedPromptTiming(
                    id: merged[index].id,
                    text: timing.text,
                    sentAt: timing.sentAt,
                    completedAt: timing.completedAt
                )
                nextLocalIndex = index
            } else {
                merged.append(timing)
            }
        }
        return merged.sorted { $0.sentAt < $1.sentAt }
    }

    private static func promptText(agentType: AgentType, object: [String: Any]) -> String? {
        switch agentType {
        case .codex:
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any],
                  payload["type"] as? String == "user_message" else { return nil }
            return normalized(payload["message"] as? String ?? "").nilIfEmpty
        case .claude:
            guard object["type"] as? String == "user",
                  let message = object["message"] as? [String: Any] else { return nil }
            let content = message["content"]
            if let text = content as? String {
                return normalized(text).nilIfEmpty
            }
            let blocks = content as? [[String: Any]] ?? []
            let text = blocks.compactMap { block -> String? in
                guard block["type"] as? String == "text" else { return nil }
                return block["text"] as? String
            }.joined(separator: "\n\n")
            return normalized(text).nilIfEmpty
        case .custom:
            return nil
        }
    }

    private static func isCompletion(agentType: AgentType, object: [String: Any]) -> Bool {
        switch agentType {
        case .codex:
            guard object["type"] as? String == "event_msg",
                  let payload = object["payload"] as? [String: Any] else { return false }
            let type = payload["type"] as? String
            return type == "task_complete" || type == "turn_aborted"
        case .claude:
            return object["type"] as? String == "result"
        case .custom:
            return false
        }
    }

    private static func sessionURL(agentType: AgentType, sessionID: String, homeDirectory: URL) -> URL? {
        let root: URL
        switch agentType {
        case .claude:
            root = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        case .codex:
            root = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        case .custom:
            return nil
        }
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return nil }
        return enumerator.compactMap { $0 as? URL }.first {
            $0.pathExtension == "jsonl" && $0.lastPathComponent.contains(sessionID)
        }
    }

    private static func date(from value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractionalFormatter.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
