import Foundation
import MagentModels

public enum ChatMessageDisplayKind: Sendable, Equatable {
    case message
    case tool(ChatToolTranscriptPresentation)
    case status(ChatMessageStatusPresentation)
}

public enum ChatMessageStatusKind: String, Sendable, Equatable {
    case cancellation
    case approvalRequired
    case error
}

public struct ChatMessageStatusPresentation: Sendable, Equatable {
    public var kind: ChatMessageStatusKind
    public var title: String
    public var detail: String?

    public init(kind: ChatMessageStatusKind, title: String, detail: String? = nil) {
        self.kind = kind
        self.title = title
        self.detail = detail
    }
}

public struct ChatMessageDisplayPlan: Sendable, Equatable {
    public var role: ChatMessageRole
    public var kind: ChatMessageDisplayKind

    public init(role: ChatMessageRole, kind: ChatMessageDisplayKind) {
        self.role = role
        self.kind = kind
    }
}

public enum ChatMessageDisplayPlanner {
    public static func plan(for message: PersistedChatMessage) -> ChatMessageDisplayPlan {
        if let persistedToolEvent = message.toolEvent {
            return ChatMessageDisplayPlan(
                role: .assistant,
                kind: .tool(ChatToolTranscriptFormatter.presentation(for: persistedToolEvent))
            )
        }
        if case .tool(let parsedToolEvent) = ChatToolTranscriptFormatter.event(for: message.text) {
            return ChatMessageDisplayPlan(
                role: .assistant,
                kind: .tool(ChatToolTranscriptFormatter.presentation(for: parsedToolEvent))
            )
        }
        if let status = statusPresentation(for: message.text), message.role == .assistant {
            return ChatMessageDisplayPlan(role: .assistant, kind: .status(status))
        }
        return ChatMessageDisplayPlan(role: message.role, kind: .message)
    }

    private static func statusPresentation(for text: String) -> ChatMessageStatusPresentation? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed == ChatBusyStateRecovery.cancelledPlaceholderText {
            return ChatMessageStatusPresentation(
                kind: .cancellation,
                title: trimmed
            )
        }

        if let codexFailure = trimmed.value(afterPrefix: "Codex app-server failed:") {
            let normalized = codexFailure.trimmingCharacters(in: .whitespacesAndNewlines)
            if isApprovalBlockedText(normalized) {
                return ChatMessageStatusPresentation(
                    kind: .approvalRequired,
                    title: normalized.nilIfBlank ?? trimmed
                )
            }
            return ChatMessageStatusPresentation(
                kind: .error,
                title: "Codex app-server failed",
                detail: normalized.nilIfBlank
            )
        }

        let lowercased = trimmed.lowercased()
        if lowercased.contains(" chat failed")
            || lowercased.hasPrefix("blocked:")
            || lowercased.hasPrefix("error:") {
            return ChatMessageStatusPresentation(kind: .error, title: trimmed)
        }

        return nil
    }

    private static func isApprovalBlockedText(_ text: String) -> Bool {
        let lowercased = text.lowercased()
        return lowercased.contains("requested approval")
            || lowercased.contains("cannot approve yet")
            || lowercased.contains("request approval")
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func value(afterPrefix prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
