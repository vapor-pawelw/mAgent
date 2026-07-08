import Foundation
import MagentModels

public enum ClaudeChatTranscriptReconciler {
    public static func reconciledChatTabsForRestore(
        _ chatTabs: [PersistedChatTab],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (chatTabs: [PersistedChatTab], didMutate: Bool) {
        var updatedTabs = chatTabs
        var didMutate = false

        for index in updatedTabs.indices {
            guard updatedTabs[index].agentType == .claude,
                  let claudeSessionID = updatedTabs[index].conversationSessionID else {
                continue
            }
            let reconciled = reconciledMessages(
                existingMessages: updatedTabs[index].messages,
                claudeSessionID: claudeSessionID,
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
        claudeSessionID: String,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> (messages: [PersistedChatMessage], didMutate: Bool) {
        guard let sessionURL = claudeSessionURL(sessionID: claudeSessionID, homeDirectory: homeDirectory),
              let jsonl = try? String(contentsOf: sessionURL, encoding: .utf8) else {
            return (existingMessages, false)
        }

        let parsedMessages = messages(fromClaudeJSONL: jsonl, existingMessages: existingMessages)
        guard !parsedMessages.isEmpty, parsedMessages != existingMessages else {
            return (existingMessages, false)
        }

        return (parsedMessages, true)
    }

    public static func messages(
        fromClaudeJSONL jsonl: String,
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
        var latestHumanUserMessageAt: Date?
        var latestAssistantTextAt: Date?
        var latestResultAt: Date?
        var pendingToolsByID: [String: (name: String, arguments: String, messageIndex: Int)] = [:]
        var pendingToolsInOrder: [(name: String, arguments: String, messageIndex: Int)] = []

        func appendMessage(
            role: ChatMessageRole,
            text: String,
            createdAt: Date?,
            toolEvent: PersistedChatToolEvent? = nil
        ) {
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
                reasoningLevel: existing?.reasoningLevel,
                toolEvent: existing?.toolEvent ?? toolEvent
            ))
        }

        func appendToolCall(name: String, arguments: String, id: String?, createdAt: Date?) {
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
            if let id, !id.isEmpty {
                pendingToolsByID[id] = (name, arguments, messageIndex)
            } else {
                pendingToolsInOrder.append((name, arguments, messageIndex))
            }
        }

        func appendOrMergeToolResult(content: String, toolUseID: String?, createdAt: Date?) {
            let pending: (name: String, arguments: String, messageIndex: Int)?
            if let toolUseID, !toolUseID.isEmpty {
                pending = pendingToolsByID.removeValue(forKey: toolUseID)
            } else if !pendingToolsInOrder.isEmpty {
                pending = pendingToolsInOrder.removeFirst()
            } else {
                pending = nil
            }

            if let pending, messages.indices.contains(pending.messageIndex) {
                let text = ChatToolTranscriptFormatter.toolResultText(
                    name: pending.name,
                    arguments: pending.arguments,
                    output: content
                )
                let toolEvent = ChatToolTranscriptFormatter.event(for: text).flatMap { event -> PersistedChatToolEvent? in
                    guard case .tool(let parsedToolEvent) = event else { return nil }
                    return ChatToolTranscriptFormatter.persistedEvent(from: parsedToolEvent)
                }
                messages[pending.messageIndex].text = text
                messages[pending.messageIndex].toolEvent = toolEvent
                lastAppended = (messages[pending.messageIndex].role, messages[pending.messageIndex].text)
            } else {
                let text = ChatToolTranscriptFormatter.toolOutputText(content)
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
                  let event = try? decoder.decode(ClaudeSessionLine.self, from: data) else {
                continue
            }

            switch event.type {
            case "user":
                let userText = event.message?.content.userVisibleText ?? ""
                if !userText.isEmpty {
                    latestHumanUserMessageAt = event.timestamp ?? latestHumanUserMessageAt
                    appendMessage(role: .user, text: userText, createdAt: event.timestamp)
                }
                for toolResult in event.message?.content.toolResults ?? [] {
                    appendOrMergeToolResult(
                        content: toolResult.content,
                        toolUseID: toolResult.toolUseID,
                        createdAt: event.timestamp
                    )
                }
            case "assistant":
                for toolUse in event.message?.content.toolUses ?? [] {
                    appendToolCall(
                        name: toolUse.name ?? "tool",
                        arguments: toolUse.arguments,
                        id: toolUse.id,
                        createdAt: event.timestamp
                    )
                }
                let assistantText = event.message?.content.text ?? ""
                if !assistantText.isEmpty {
                    latestAssistantTextAt = event.timestamp ?? latestAssistantTextAt
                    appendMessage(role: .assistant, text: assistantText, createdAt: event.timestamp)
                }
                if event.message?.stopReason == "end_turn" || event.message?.stopReason == "stop_sequence" {
                    latestResultAt = event.timestamp ?? latestResultAt
                }
            case "result":
                latestResultAt = event.timestamp ?? latestResultAt
            default:
                continue
            }
        }

        if let latestHumanUserMessageAt {
            let assistantAfterLatestUser = latestAssistantTextAt.map { $0 >= latestHumanUserMessageAt } ?? false
            let completedAfterLatestUser = latestResultAt.map { $0 >= latestHumanUserMessageAt } ?? false
            if !assistantAfterLatestUser, !completedAfterLatestUser {
                appendMessage(
                    role: .assistant,
                    text: "Thinking...",
                    createdAt: latestHumanUserMessageAt
                )
            }
        }

        return messages
    }

    private static func claudeSessionURL(sessionID: String, homeDirectory: URL) -> URL? {
        let projectsURL = homeDirectory.appendingPathComponent(".claude/projects", isDirectory: true)
        let exactMatch = projectsURL
            .appendingPathComponent(sessionID)
            .appendingPathExtension("jsonl")
        if FileManager.default.fileExists(atPath: exactMatch.path) {
            return exactMatch
        }

        guard let enumerator = FileManager.default.enumerator(
            at: projectsURL,
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

private struct ClaudeSessionLine: Decodable {
    var type: String
    var timestamp: Date?
    var message: Message?

    struct Message: Decodable {
        var role: String?
        var content: ClaudeContent
        var stopReason: String?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case stopReason = "stop_reason"
        }
    }
}

private enum ClaudeContent: Decodable {
    case string(String)
    case blocks([ClaudeContentBlock])

    var text: String {
        switch self {
        case let .string(value):
            return value
        case let .blocks(blocks):
            return blocks.compactMap(\.text).joined(separator: "\n\n")
        }
    }

    var userVisibleText: String {
        switch self {
        case let .string(value):
            return value
        case let .blocks(blocks):
            return blocks.compactMap { block in
                if case .text = block {
                    return block.text
                }
                return nil
            }.joined(separator: "\n\n")
        }
    }

    var toolUses: [(id: String?, name: String?, arguments: String)] {
        guard case let .blocks(blocks) = self else { return [] }
        return blocks.compactMap { block in
            guard case let .toolUse(id, name, input) = block else { return nil }
            let renderedInput = input?.rendered ?? ""
            return (id, name, renderedInput)
        }
    }

    var toolResults: [(toolUseID: String?, content: String)] {
        guard case let .blocks(blocks) = self else { return [] }
        return blocks.compactMap { block in
            guard case let .toolResult(toolUseID, content) = block else { return nil }
            return (toolUseID, content)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            self = .blocks((try? container.decode([ClaudeContentBlock].self)) ?? [])
        }
    }
}

private enum ClaudeContentBlock: Decodable {
    case text(String)
    case toolUse(id: String?, name: String?, input: ClaudeJSONValue?)
    case toolResult(toolUseID: String?, content: String)
    case other

    var text: String? {
        guard case let .text(value) = self else { return nil }
        return value
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case id
        case name
        case input
        case content
        case toolUseID = "tool_use_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decodeIfPresent(String.self, forKey: .type) {
        case "text":
            self = .text(try container.decodeIfPresent(String.self, forKey: .text) ?? "")
        case "tool_use":
            self = .toolUse(
                id: try container.decodeIfPresent(String.self, forKey: .id),
                name: try container.decodeIfPresent(String.self, forKey: .name),
                input: try container.decodeIfPresent(ClaudeJSONValue.self, forKey: .input)
            )
        case "tool_result":
            let content = (try? container.decode(String.self, forKey: .content))
                ?? (try? container.decode([ClaudeContentBlock].self, forKey: .content).compactMap(\.text).joined(separator: "\n\n"))
                ?? ""
            self = .toolResult(
                toolUseID: try container.decodeIfPresent(String.self, forKey: .toolUseID),
                content: content
            )
        default:
            self = .other
        }
    }
}

private enum ClaudeJSONValue: Decodable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: ClaudeJSONValue])
    case array([ClaudeJSONValue])
    case null

    var rendered: String {
        switch self {
        case let .string(value):
            return value
        case let .number(value):
            return String(value)
        case let .bool(value):
            return String(value)
        case let .object(value):
            let parts = value.keys.sorted().map { "\"\($0)\": \(value[$0]?.rendered ?? "null")" }
            return "{\(parts.joined(separator: ", "))}"
        case let .array(value):
            return "[\(value.map(\.rendered).joined(separator: ", "))]"
        case .null:
            return "null"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: ClaudeJSONValue].self) {
            self = .object(value)
        } else {
            self = .array((try? container.decode([ClaudeJSONValue].self)) ?? [])
        }
    }
}
