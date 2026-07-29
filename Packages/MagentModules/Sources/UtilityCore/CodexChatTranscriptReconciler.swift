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
        var exactExistingIndices: [ChatMessageMatchKey: [Int]] = [:]
        var canonicalUserIndices: [String: [Int]] = [:]
        for (index, message) in existingMessages.enumerated() {
            let trimmed = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
            exactExistingIndices[
                ChatMessageMatchKey(roleRawValue: message.role.rawValue, text: trimmed),
                default: []
            ].append(index)
            if message.role == .user {
                canonicalUserIndices[canonicalUserText(trimmed), default: []].append(index)
            }
        }
        var exactExistingCursors: [ChatMessageMatchKey: Int] = [:]
        var canonicalUserCursors: [String: Int] = [:]
        var consumedExistingIndices = Set<Int>()
        var parsedIndexByExistingIndex: [Int: Int] = [:]

        func takeNextIndex(from indices: [Int]?, cursor: inout Int) -> Int? {
            guard let indices else { return nil }
            while cursor < indices.count {
                let candidate = indices[cursor]
                cursor += 1
                if consumedExistingIndices.insert(candidate).inserted {
                    return candidate
                }
            }
            return nil
        }

        func takeExistingIndex(role: ChatMessageRole, text: String) -> Int? {
            let exactKey = ChatMessageMatchKey(roleRawValue: role.rawValue, text: text)
            var exactCursor = exactExistingCursors[exactKey] ?? 0
            if let index = takeNextIndex(
                from: exactExistingIndices[exactKey],
                cursor: &exactCursor
            ) {
                exactExistingCursors[exactKey] = exactCursor
                return index
            }
            exactExistingCursors[exactKey] = exactCursor

            guard role == .user else { return nil }
            let canonicalText = canonicalUserText(text)
            var canonicalCursor = canonicalUserCursors[canonicalText] ?? 0
            let index = takeNextIndex(
                from: canonicalUserIndices[canonicalText],
                cursor: &canonicalCursor
            )
            canonicalUserCursors[canonicalText] = canonicalCursor
            return index
        }

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

            let existingIndex = takeExistingIndex(role: role, text: trimmed)
            let existing = existingIndex.map { existingMessages[$0] }
            messages.append(PersistedChatMessage(
                id: existing?.id ?? UUID(),
                role: role,
                text: trimmed,
                attachments: existing?.attachments ?? attachments,
                createdAt: existing?.createdAt ?? createdAt ?? Date(),
                modelId: existing?.modelId,
                reasoningLevel: existing?.reasoningLevel,
                toolEvent: existing?.toolEvent ?? toolEvent,
                origin: existing?.origin ?? .agentTranscript
            ))
            if let existingIndex {
                parsedIndexByExistingIndex[existingIndex] = messages.count - 1
            }
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

        return mergingLocalMessages(
            existingMessages,
            parsedMessages: messages,
            parsedIndexByExistingIndex: parsedIndexByExistingIndex
        )
    }

    private static func mergingLocalMessages(
        _ existingMessages: [PersistedChatMessage],
        parsedMessages: [PersistedChatMessage],
        parsedIndexByExistingIndex: [Int: Int]
    ) -> [PersistedChatMessage] {
        var merged: [PersistedChatMessage] = []
        var parsedCursor = 0

        for (existingIndex, existingMessage) in existingMessages.enumerated() {
            if let parsedIndex = parsedIndexByExistingIndex[existingIndex],
               parsedIndex >= parsedCursor {
                merged.append(contentsOf: parsedMessages[parsedCursor...parsedIndex])
                parsedCursor = parsedIndex + 1
            } else if shouldRetainLocalMessage(existingMessage) {
                merged.append(existingMessage)
            }
        }

        if parsedCursor < parsedMessages.count {
            merged.append(contentsOf: parsedMessages[parsedCursor...])
        }
        return merged
    }

    private static func shouldRetainLocalMessage(_ message: PersistedChatMessage) -> Bool {
        if message.origin == .localUI || message.role == .system {
            return true
        }
        if case .status = ChatMessageDisplayPlanner.plan(for: message).kind {
            return true
        }
        guard message.role == .assistant else { return false }
        let text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return legacyLocalAssistantPrefixes.contains(where: text.hasPrefix)
    }

    private static let legacyLocalAssistantPrefixes = [
        "Available slash commands:",
        "Codex chat supports ",
        "Current model:",
        "No model selected.",
        "Unknown model:",
        "Model changed to ",
        "Current reasoning effort:",
        "No reasoning effort selected.",
        "Unsupported reasoning effort:",
        "Reasoning effort set to ",
    ]

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

private struct ChatMessageMatchKey: Hashable {
    let roleRawValue: String
    let text: String
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
