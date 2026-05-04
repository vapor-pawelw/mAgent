import Foundation
import MagentModels

public enum ChatBusyStateRecovery {
    public static let cancelledPlaceholderText = "Request cancelled."

    public static func isAssistantLoadingPlaceholder(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed == "Thinking."
            || trimmed == "Thinking.."
            || trimmed == "Thinking..."
            || trimmed == "Thinking…"
            || trimmed.hasPrefix("Working (")
    }

    public static func normalizedMessagesForAppRelaunch(
        _ messages: [PersistedChatMessage]
    ) -> (messages: [PersistedChatMessage], didMutate: Bool) {
        var normalized = messages
        var didMutate = false

        for index in normalized.indices {
            guard normalized[index].role == .assistant else { continue }
            guard isAssistantLoadingPlaceholder(normalized[index].text) else { continue }
            normalized[index].text = cancelledPlaceholderText
            didMutate = true
        }

        return (normalized, didMutate)
    }

    /// Removes any loading placeholders before a brand-new turn begins.
    /// This prevents stranded "Working/Thinking" bubbles from duplicating
    /// when a previous turn ended unexpectedly.
    public static func normalizedMessagesForNewRequest(
        _ messages: [PersistedChatMessage]
    ) -> (messages: [PersistedChatMessage], didMutate: Bool) {
        var normalized: [PersistedChatMessage] = []
        normalized.reserveCapacity(messages.count)
        var didMutate = false

        for message in messages {
            if message.role == .assistant, isAssistantLoadingPlaceholder(message.text) {
                didMutate = true
                continue
            }
            normalized.append(message)
        }

        return (normalized, didMutate)
    }

    public static func normalizedChatTabsForAppRelaunch(
        _ chatTabs: [PersistedChatTab]
    ) -> (chatTabs: [PersistedChatTab], didMutate: Bool) {
        var normalizedTabs = chatTabs
        var didMutate = false

        for index in normalizedTabs.indices {
            let normalizedMessages = normalizedMessagesForAppRelaunch(normalizedTabs[index].messages)
            guard normalizedMessages.didMutate else { continue }
            normalizedTabs[index].messages = normalizedMessages.messages
            didMutate = true
        }

        return (normalizedTabs, didMutate)
    }
}
