import Foundation
import MagentModels

public enum CodexChatTranscriptReconciler {
    public static func reconciledMessages(
        existingMessages: [PersistedChatMessage],
        codexSessionID: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (messages: [PersistedChatMessage], didMutate: Bool) {
        guard let sessionURL = codexSessionURL(sessionID: codexSessionID, homeDirectory: homeDirectory),
              let jsonl = try? String(contentsOf: sessionURL, encoding: .utf8) else {
            return (existingMessages, false)
        }

        let parsedMessages = messages(fromCodexJSONL: jsonl, existingMessages: existingMessages)
        guard !parsedMessages.isEmpty, parsedMessages != existingMessages else {
            return (existingMessages, false)
        }

        return (parsedMessages, true)
    }

    public static func messages(
        fromCodexJSONL jsonl: String,
        existingMessages: [PersistedChatMessage] = []
    ) -> [PersistedChatMessage] {
        let existingUsersByText = Dictionary(
            existingMessages.filter { $0.role == .user }.map { ($0.text, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingAssistantsByText = Dictionary(
            existingMessages.filter { $0.role == .assistant }.map { ($0.text, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let existingSystemsByText = Dictionary(
            existingMessages.filter { $0.role == .system }.map { ($0.text, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var messages: [PersistedChatMessage] = []
        var lastAppended: (role: ChatMessageRole, text: String)?

        func appendMessage(role: ChatMessageRole, text: String, createdAt: Date?) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if lastAppended?.role == role, lastAppended?.text == trimmed {
                return
            }
            lastAppended = (role, trimmed)

            let existing: PersistedChatMessage? = switch role {
            case .user: existingUsersByText[trimmed]
            case .assistant: existingAssistantsByText[trimmed]
            case .system: existingSystemsByText[trimmed]
            }
            messages.append(PersistedChatMessage(
                id: existing?.id ?? UUID(),
                role: role,
                text: trimmed,
                attachments: existing?.attachments ?? [],
                createdAt: existing?.createdAt ?? createdAt ?? Date(),
                modelId: existing?.modelId,
                reasoningLevel: existing?.reasoningLevel
            ))
        }

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(CodexSessionLine.self, from: data) else {
                continue
            }

            switch (event.type, event.payload?.type) {
            case ("event_msg", "user_message"):
                appendMessage(role: .user, text: event.payload?.message ?? "", createdAt: event.timestamp)
            case ("event_msg", "agent_message"):
                appendMessage(role: .assistant, text: event.payload?.message ?? "", createdAt: event.timestamp)
            case ("response_item", "function_call"):
                guard let payload = event.payload else { continue }
                let name = payload.name ?? "tool"
                let arguments = payload.arguments ?? ""
                appendMessage(
                    role: .system,
                    text: "Tool call: \(name)\n\(arguments)",
                    createdAt: event.timestamp
                )
            case ("response_item", "function_call_output"):
                guard let payload = event.payload else { continue }
                let output = payload.output ?? ""
                appendMessage(
                    role: .system,
                    text: "Tool output:\n\(output)",
                    createdAt: event.timestamp
                )
            case ("response_item", "custom_tool_call"):
                guard let payload = event.payload else { continue }
                appendMessage(
                    role: .system,
                    text: "Tool call: \(payload.name ?? "custom")\n\(payload.input ?? "")",
                    createdAt: event.timestamp
                )
            case ("response_item", "custom_tool_call_output"):
                guard let payload = event.payload else { continue }
                appendMessage(
                    role: .system,
                    text: "Tool output:\n\(payload.output ?? "")",
                    createdAt: event.timestamp
                )
            default:
                continue
            }
        }

        return messages
    }

    private static func codexSessionURL(sessionID: String, homeDirectory: URL) -> URL? {
        let sessionsURL = homeDirectory.appendingPathComponent(".codex/sessions", isDirectory: true)
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl",
                  url.lastPathComponent.contains(sessionID) else {
                continue
            }
            return url
        }
        return nil
    }
}

private struct CodexSessionLine: Decodable {
    var timestamp: Date?
    var type: String
    var payload: Payload?

    struct Payload: Decodable {
        var type: String?
        var message: String?
        var name: String?
        var arguments: String?
        var output: String?
        var input: String?
    }
}
