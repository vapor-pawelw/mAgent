import Foundation
import Testing
import MagentCore

@Suite("Chat busy-state recovery")
struct ChatBusyStateRecoveryTests {

    @Test("Converts stale assistant loading placeholders after relaunch")
    func convertsLoadingPlaceholders() {
        let assistantThinking = PersistedChatMessage(role: .assistant, text: "Thinking...")
        let assistantWorking = PersistedChatMessage(role: .assistant, text: "Working (42s • esc to interrupt)")
        let userMessage = PersistedChatMessage(role: .user, text: "hello")

        let result = ChatBusyStateRecovery.normalizedMessagesForAppRelaunch(
            [assistantThinking, assistantWorking, userMessage]
        )

        #expect(result.didMutate)
        #expect(result.messages[0].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.messages[1].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.messages[2].text == "hello")
    }

    @Test("Leaves non-loading assistant text unchanged")
    func keepsRegularAssistantMessages() {
        let assistant = PersistedChatMessage(role: .assistant, text: "Done.")

        let result = ChatBusyStateRecovery.normalizedMessagesForAppRelaunch([assistant])

        #expect(!result.didMutate)
        #expect(result.messages[0].text == "Done.")
    }

    @Test("Normalizes loading placeholders across persisted chat tabs")
    func normalizesPersistedChatTabs() {
        let loadingTab = PersistedChatTab(
            identifier: "chat-1",
            agentType: .codex,
            title: "Chat",
            messages: [
                PersistedChatMessage(role: .user, text: "hello"),
                PersistedChatMessage(role: .assistant, text: "Thinking…"),
            ]
        )
        let completedTab = PersistedChatTab(
            identifier: "chat-2",
            agentType: .claude,
            title: "Done",
            messages: [
                PersistedChatMessage(role: .assistant, text: "Done."),
            ]
        )

        let result = ChatBusyStateRecovery.normalizedChatTabsForAppRelaunch([loadingTab, completedTab])

        #expect(result.didMutate)
        #expect(result.chatTabs[0].messages[1].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.chatTabs[1].messages[0].text == "Done.")
    }

    @Test("Removes stranded loading placeholders before starting a new request")
    func removesLoadingPlaceholdersBeforeNewRequest() {
        let userOne = PersistedChatMessage(role: .user, text: "first")
        let loadingOne = PersistedChatMessage(role: .assistant, text: "Thinking...")
        let assistantDone = PersistedChatMessage(role: .assistant, text: "done")
        let loadingTwo = PersistedChatMessage(role: .assistant, text: "Working (9s • esc to interrupt)")
        let cancelled = PersistedChatMessage(role: .assistant, text: ChatBusyStateRecovery.cancelledPlaceholderText)

        let result = ChatBusyStateRecovery.normalizedMessagesForNewRequest(
            [userOne, loadingOne, assistantDone, loadingTwo, cancelled]
        )

        #expect(result.didMutate)
        #expect(result.messages == [userOne, assistantDone, cancelled])
    }
}
