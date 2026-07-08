import Foundation
import MagentModels

public enum CodexChatTranscriptReconciler {
    public static func reconciledChatTabsForRestore(
        _ chatTabs: [PersistedChatTab],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (chatTabs: [PersistedChatTab], didMutate: Bool) {
        var updatedTabs = chatTabs
        var didMutate = false

        for index in updatedTabs.indices {
            guard updatedTabs[index].agentType == .codex,
                  let codexSessionID = updatedTabs[index].conversationSessionID else {
                continue
            }
            let reconciled = reconciledMessages(
                existingMessages: updatedTabs[index].messages,
                codexSessionID: codexSessionID,
                homeDirectory: homeDirectory
            )
            guard reconciled.didMutate else { continue }
            updatedTabs[index].messages = reconciled.messages
            didMutate = true
        }

        return (updatedTabs, didMutate)
    }

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
        let existingUsersByCanonicalText = Dictionary(
            existingMessages.filter { $0.role == .user }.map { (canonicalUserText($0.text), $0) },
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
        var latestUserMessageAt: Date?
        var latestCompletionAt: Date?
        var latestAbortAt: Date?
        var pendingToolsByCallID: [String: (name: String, arguments: String, messageIndex: Int)] = [:]
        var pendingToolsInOrder: [(name: String, arguments: String, messageIndex: Int)] = []
        var seenUserMessagesByCanonicalText: [String: Date] = [:]
        var suppressMessagesForDuplicateUserReplay = false

        func appendMessage(
            role: ChatMessageRole,
            text: String,
            createdAt: Date?,
            attachments: [PersistedChatAttachment] = [],
            toolEvent: PersistedChatToolEvent? = nil
        ) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if lastAppended?.role == role, lastAppended?.text == trimmed {
                return
            }
            lastAppended = (role, trimmed)

            let existing: PersistedChatMessage? = switch role {
            case .user: existingUsersByText[trimmed] ?? existingUsersByCanonicalText[canonicalUserText(trimmed)]
            case .assistant: existingAssistantsByText[trimmed]
            case .system: existingSystemsByText[trimmed]
            }
            messages.append(PersistedChatMessage(
                id: existing?.id ?? UUID(),
                role: role,
                text: trimmed,
                attachments: existing?.attachments ?? attachments,
                createdAt: existing?.createdAt ?? createdAt ?? Date(),
                modelId: existing?.modelId,
                reasoningLevel: existing?.reasoningLevel,
                toolEvent: existing?.toolEvent ?? toolEvent
            ))
        }

        func appendToolCall(name: String, arguments: String, callID: String?, createdAt: Date?) {
            let text = ChatToolTranscriptFormatter.toolCallText(name: name, arguments: arguments)
            let toolEvent = ChatToolTranscriptFormatter.event(for: text).flatMap { event -> PersistedChatToolEvent? in
                guard case .tool(let parsedToolEvent) = event else { return nil }
                return ChatToolTranscriptFormatter.persistedEvent(from: parsedToolEvent)
            }
            appendMessage(
                role: .assistant,
                text: text,
                createdAt: createdAt,
                toolEvent: toolEvent
            )
            guard let messageIndex = messages.indices.last else { return }
            if let callID, !callID.isEmpty {
                pendingToolsByCallID[callID] = (name, arguments, messageIndex)
            } else {
                pendingToolsInOrder.append((name, arguments, messageIndex))
            }
        }

        func appendOrMergeToolOutput(output: String, callID: String?, createdAt: Date?) {
            let pending: (name: String, arguments: String, messageIndex: Int)?
            if let callID, !callID.isEmpty {
                pending = pendingToolsByCallID.removeValue(forKey: callID)
            } else if !pendingToolsInOrder.isEmpty {
                pending = pendingToolsInOrder.removeFirst()
            } else {
                pending = nil
            }

            if let pending, messages.indices.contains(pending.messageIndex) {
                let text = ChatToolTranscriptFormatter.toolResultText(
                    name: pending.name,
                    arguments: pending.arguments,
                    output: output
                )
                let toolEvent = ChatToolTranscriptFormatter.event(for: text).flatMap { event -> PersistedChatToolEvent? in
                    guard case .tool(let parsedToolEvent) = event else { return nil }
                    return ChatToolTranscriptFormatter.persistedEvent(from: parsedToolEvent)
                }
                messages[pending.messageIndex].text = text
                messages[pending.messageIndex].toolEvent = toolEvent
                lastAppended = (messages[pending.messageIndex].role, messages[pending.messageIndex].text)
            } else {
                let text = ChatToolTranscriptFormatter.toolOutputText(output)
                let toolEvent = ChatToolTranscriptFormatter.event(for: text).flatMap { event -> PersistedChatToolEvent? in
                    guard case .tool(let parsedToolEvent) = event else { return nil }
                    return ChatToolTranscriptFormatter.persistedEvent(from: parsedToolEvent)
                }
                appendMessage(
                    role: .assistant,
                    text: text,
                    createdAt: createdAt,
                    toolEvent: toolEvent
                )
            }
        }

        for line in jsonl.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = String(line).data(using: .utf8),
                  let event = try? decoder.decode(CodexSessionLine.self, from: data) else {
                continue
            }

            switch (event.type, event.payload?.type) {
            case ("event_msg", "user_message"):
                let text = event.payload?.message ?? ""
                let canonicalText = canonicalUserText(text)
                if let previousDate = seenUserMessagesByCanonicalText[canonicalText],
                   let timestamp = event.timestamp,
                   timestamp.timeIntervalSince(previousDate) < 15 * 60 {
                    suppressMessagesForDuplicateUserReplay = true
                    continue
                }
                suppressMessagesForDuplicateUserReplay = false
                latestUserMessageAt = event.timestamp ?? latestUserMessageAt
                if !canonicalText.isEmpty {
                    seenUserMessagesByCanonicalText[canonicalText] = event.timestamp ?? Date()
                }
                appendMessage(
                    role: .user,
                    text: canonicalText.isEmpty ? text : canonicalText,
                    createdAt: event.timestamp,
                    attachments: attachments(from: event.payload)
                )
            case ("event_msg", "agent_message"):
                guard !suppressMessagesForDuplicateUserReplay else { continue }
                appendMessage(role: .assistant, text: event.payload?.message ?? "", createdAt: event.timestamp)
            case ("event_msg", "task_complete"):
                latestCompletionAt = event.timestamp ?? latestCompletionAt
            case ("event_msg", "turn_aborted"):
                latestAbortAt = event.timestamp ?? latestAbortAt
            case ("response_item", "function_call"):
                guard !suppressMessagesForDuplicateUserReplay else { continue }
                guard let payload = event.payload else { continue }
                let name = payload.name ?? "tool"
                let arguments = payload.arguments ?? ""
                appendToolCall(name: name, arguments: arguments, callID: payload.callID, createdAt: event.timestamp)
            case ("response_item", "function_call_output"):
                guard !suppressMessagesForDuplicateUserReplay else { continue }
                guard let payload = event.payload else { continue }
                let output = payload.output ?? ""
                appendOrMergeToolOutput(output: output, callID: payload.callID, createdAt: event.timestamp)
            case ("response_item", "custom_tool_call"):
                guard !suppressMessagesForDuplicateUserReplay else { continue }
                guard let payload = event.payload else { continue }
                let name = payload.name ?? "custom"
                appendToolCall(name: name, arguments: payload.input ?? "", callID: payload.callID, createdAt: event.timestamp)
            case ("response_item", "custom_tool_call_output"):
                guard !suppressMessagesForDuplicateUserReplay else { continue }
                guard let payload = event.payload else { continue }
                appendOrMergeToolOutput(output: payload.output ?? "", callID: payload.callID, createdAt: event.timestamp)
            default:
                continue
            }
        }

        if let latestUserMessageAt {
            let completedAfterLatestUser = latestCompletionAt.map { $0 >= latestUserMessageAt } ?? false
            let abortedAfterLatestUser = latestAbortAt.map { $0 >= latestUserMessageAt } ?? false
            if !completedAfterLatestUser, !abortedAfterLatestUser {
                appendMessage(
                    role: .assistant,
                    text: "Thinking...",
                    createdAt: latestUserMessageAt
                )
            }
        }

        return messages
    }

    private static func canonicalUserText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = trimmed.range(of: "\n\nAttached files:\n") else {
            return trimmed
        }
        return String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func attachments(from payload: CodexSessionLine.Payload?) -> [PersistedChatAttachment] {
        guard let payload else { return [] }
        return payload.localImages.compactMap { path in
            let normalizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard FileManager.default.fileExists(atPath: normalizedPath) else { return nil }
            return PersistedChatAttachment(filePath: normalizedPath, kind: .image)
        }
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
        var callID: String?
        var localImages: [String]

        enum CodingKeys: String, CodingKey {
            case type
            case message
            case name
            case arguments
            case output
            case input
            case callID = "call_id"
            case localImages = "local_images"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decodeIfPresent(String.self, forKey: .type)
            message = try container.decodeIfPresent(String.self, forKey: .message)
            name = try container.decodeIfPresent(String.self, forKey: .name)
            arguments = try container.decodeIfPresent(String.self, forKey: .arguments)
            output = try container.decodeIfPresent(String.self, forKey: .output)
            input = try container.decodeIfPresent(String.self, forKey: .input)
            callID = try container.decodeIfPresent(String.self, forKey: .callID)
            localImages = try container.decodeIfPresent([String].self, forKey: .localImages) ?? []
        }
    }
}
