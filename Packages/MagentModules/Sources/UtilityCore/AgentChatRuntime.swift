import Foundation
import MagentModels
import ShellInfra

public nonisolated struct AgentChatExecutionResult: Sendable, Equatable {
    public let assistantText: String
    public let conversationSessionID: String?

    public init(assistantText: String, conversationSessionID: String?) {
        self.assistantText = assistantText
        self.conversationSessionID = conversationSessionID
    }
}

public nonisolated enum AgentChatRuntime {

    public nonisolated static func execute(
        agentType: AgentType,
        prompt: String,
        workingDirectory: String,
        conversationSessionID: String? = nil,
        claudeSystemPrompt: String? = nil,
        modelId: String? = nil,
        reasoningLevel: String? = nil,
        cancellationHandle: ShellExecutor.CancellationHandle? = nil
    ) async -> AgentChatExecutionResult {
        if Task.isCancelled {
            return AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            )
        }

        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            return AgentChatExecutionResult(assistantText: "Prompt is empty.", conversationSessionID: normalizedSessionID(conversationSessionID))
        }

        guard let command = command(
            for: agentType,
            prompt: prompt,
            conversationSessionID: conversationSessionID,
            claudeSystemPrompt: claudeSystemPrompt,
            modelId: modelId,
            reasoningLevel: reasoningLevel
        ) else {
            return AgentChatExecutionResult(
                assistantText: "Chat is not supported for \(agentType.displayName).",
                conversationSessionID: normalizedSessionID(conversationSessionID)
            )
        }

        let result = await ShellExecutor.executeCancellable(
            command,
            workingDirectory: workingDirectory,
            cancellationHandle: cancellationHandle
        )
        let parsed = parseOutput(for: agentType, stdout: result.stdout)
        let effectiveSessionID = parsed.conversationSessionID ?? normalizedSessionID(conversationSessionID)

        if Task.isCancelled {
            return AgentChatExecutionResult(
                assistantText: "Request cancelled.",
                conversationSessionID: effectiveSessionID
            )
        }

        if result.exitCode == 0 {
            let parsedText = parsed.assistantText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !parsedText.isEmpty {
                return AgentChatExecutionResult(assistantText: parsedText, conversationSessionID: effectiveSessionID)
            }

            let fallbackText = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if !fallbackText.isEmpty {
                return AgentChatExecutionResult(assistantText: fallbackText, conversationSessionID: effectiveSessionID)
            }

            return AgentChatExecutionResult(
                assistantText: "No response from \(agentType.displayName).",
                conversationSessionID: effectiveSessionID
            )
        }

        let details = conciseErrorDetails(stderr: result.stderr, stdout: result.stdout)
        let message: String
        if let details {
            message = "\(agentType.displayName) chat failed: \(details)"
        } else {
            message = "\(agentType.displayName) chat failed (exit \(result.exitCode))."
        }

        return AgentChatExecutionResult(assistantText: message, conversationSessionID: effectiveSessionID)
    }

    public nonisolated static func parseOutput(for agentType: AgentType, stdout: String) -> AgentChatExecutionResult {
        switch agentType {
        case .claude:
            return parseClaudeStreamJSON(stdout)
        case .codex:
            return parseCodexJSONL(stdout)
        case .custom:
            return AgentChatExecutionResult(assistantText: "", conversationSessionID: nil)
        }
    }

    public nonisolated static func parseClaudeStreamJSON(_ stdout: String) -> AgentChatExecutionResult {
        var sessionID: String?
        var resultText: String?
        var assistantMessageText: String?
        var deltaBuffer: [String] = []

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let json = parseJSONObject(line) else { continue }

            if let candidateSessionID = normalizedSessionID(json["session_id"] as? String) {
                sessionID = candidateSessionID
            }

            guard let type = json["type"] as? String else { continue }

            switch type {
            case "result":
                if let text = normalizedNonEmpty(json["result"] as? String) {
                    resultText = text
                }
            case "assistant":
                guard let message = json["message"] as? [String: Any],
                      let blocks = message["content"] as? [[String: Any]] else {
                    continue
                }

                let text = blocks.compactMap { block in
                    guard let blockType = block["type"] as? String,
                          blockType == "text" else {
                        return nil
                    }
                    return block["text"] as? String
                }.joined()

                if let normalized = normalizedNonEmpty(text) {
                    assistantMessageText = normalized
                }
            case "stream_event":
                guard let event = json["event"] as? [String: Any],
                      let eventType = event["type"] as? String,
                      eventType == "content_block_delta",
                      let delta = event["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String,
                      deltaType == "text_delta",
                      let text = delta["text"] as? String,
                      !text.isEmpty else {
                    continue
                }
                deltaBuffer.append(text)
            default:
                continue
            }
        }

        let mergedDeltas = normalizedNonEmpty(deltaBuffer.joined())
        return AgentChatExecutionResult(
            assistantText: resultText ?? assistantMessageText ?? mergedDeltas ?? "",
            conversationSessionID: sessionID
        )
    }

    public nonisolated static func parseCodexJSONL(_ stdout: String) -> AgentChatExecutionResult {
        var sessionID: String?
        var assistantText: String?

        for line in stdout.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let json = parseJSONObject(line),
                  let type = json["type"] as? String else {
                continue
            }

            if type == "thread.started",
               let candidate = normalizedSessionID(json["thread_id"] as? String) {
                sessionID = candidate
                continue
            }

            if type == "item.completed",
               let item = json["item"] as? [String: Any],
               let itemType = item["type"] as? String,
               itemType == "agent_message",
               let text = normalizedNonEmpty(item["text"] as? String) {
                assistantText = text
            }
        }

        return AgentChatExecutionResult(assistantText: assistantText ?? "", conversationSessionID: sessionID)
    }

    private nonisolated static func command(
        for agentType: AgentType,
        prompt: String,
        conversationSessionID: String?,
        claudeSystemPrompt: String?,
        modelId: String?,
        reasoningLevel: String?
    ) -> String? {
        let quotedPrompt = shellQuote(prompt)
        let normalizedConversationSessionID = normalizedSessionID(conversationSessionID)
        let normalizedModelID = normalizedNonEmpty(modelId)
        let normalizedReasoningLevel = normalizedNonEmpty(reasoningLevel)

        switch agentType {
        case .claude:
            var components: [String] = [
                "command claude",
                "-p",
                quotedPrompt,
                "--output-format stream-json",
                "--verbose",
                "--include-partial-messages",
            ]

            if let normalizedModelID {
                components.append("--model \(shellQuote(normalizedModelID))")
            }
            if let normalizedReasoningLevel {
                components.append("--effort \(shellQuote(normalizedReasoningLevel))")
            }
            if let resumeID = normalizedConversationSessionID {
                components.append("--resume \(shellQuote(resumeID))")
            }

            if normalizedConversationSessionID == nil,
               let systemPrompt = normalizedNonEmpty(claudeSystemPrompt) {
                components.append("--append-system-prompt \(shellQuote(systemPrompt))")
            }

            return components.joined(separator: " ")
        case .codex:
            var components: [String] = ["command codex"]
            if let normalizedModelID {
                components.append("-m \(shellQuote(normalizedModelID))")
            }
            if let normalizedReasoningLevel {
                components.append("-c \(shellQuote("model_reasoning_effort=\"\(normalizedReasoningLevel)\""))")
            }
            if let resumeID = normalizedConversationSessionID {
                components.append("exec resume \(shellQuote(resumeID)) --json \(quotedPrompt)")
            } else {
                components.append("exec --json \(quotedPrompt)")
            }
            return components.joined(separator: " ")
        case .custom:
            return nil
        }
    }

    public nonisolated static func parseClaudeModelChange(from output: String) -> (modelLabel: String, effortLevel: String?)? {
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return lines.reversed().lazy.compactMap { parseClaudeModelChangeLine(String($0)) }.first
    }

    public nonisolated static func parseCodexModelChange(from output: String) -> (modelId: String, effortLevel: String?)? {
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        return lines.reversed().lazy.compactMap { parseCodexModelChangeLine(String($0)) }.first
    }

    private nonisolated static func parseClaudeModelChangeLine(_ line: String) -> (modelLabel: String, effortLevel: String?)? {
        let stripped = line
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "⎿" || $0 == " " })

        guard stripped.hasPrefix("Set model to ") else { return nil }

        let remainder = String(stripped.dropFirst("Set model to ".count)).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        if let withRange = remainder.range(of: #" with (\w+) effort$"#, options: .regularExpression) {
            let modelLabel = String(remainder[remainder.startIndex..<withRange.lowerBound]).trimmingCharacters(in: .whitespaces)
            let withClause = String(remainder[withRange]).trimmingCharacters(in: .whitespaces)
            let effortWord = withClause
                .replacingOccurrences(of: "^with ", with: "", options: .regularExpression)
                .replacingOccurrences(of: " effort$", with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard !modelLabel.isEmpty, !effortWord.isEmpty else { return nil }
            return (modelLabel, effortWord)
        }

        return (remainder, nil)
    }

    private nonisolated static func parseCodexModelChangeLine(_ line: String) -> (modelId: String, effortLevel: String?)? {
        let stripped = line
            .trimmingCharacters(in: .whitespaces)
            .drop(while: { $0 == "•" || $0 == " " })

        guard stripped.hasPrefix("Model changed to ") else { return nil }

        let remainder = String(stripped.dropFirst("Model changed to ".count)).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }

        let tokens = remainder.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let modelId = tokens.first, !modelId.isEmpty else { return nil }
        let effortLevel = tokens.count >= 2 ? tokens[1] : nil
        return (modelId, effortLevel)
    }

    private nonisolated static func parseJSONObject(_ line: Substring) -> [String: Any]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.first == "{", trimmed.last == "}" else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else {
            return nil
        }
        return json
    }

    private nonisolated static func conciseErrorDetails(stderr: String, stdout: String) -> String? {
        let candidates = [stderr, stdout]
        for candidate in candidates {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let firstLine = trimmed
                .split(separator: "\n", omittingEmptySubsequences: true)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !firstLine.isEmpty {
                return String(firstLine.prefix(400))
            }
            return String(trimmed.prefix(400))
        }
        return nil
    }

    private nonisolated static func normalizedSessionID(_ value: String?) -> String? {
        normalizedNonEmpty(value)
    }

    private nonisolated static func normalizedNonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}
