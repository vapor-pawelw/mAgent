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
