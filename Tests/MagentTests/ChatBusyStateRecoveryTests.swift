import Foundation
import Testing
import MagentCore

@Suite("Chat busy-state recovery")
struct ChatBusyStateRecoveryTests {

    @Test("Converts stale assistant loading placeholders after relaunch")
    func convertsLoadingPlaceholders() {
        let assistantThinking = PersistedChatMessage(role: .assistant, text: "Thinking...")
        let assistantStartingCodex = PersistedChatMessage(
            role: .assistant,
            text: ChatBusyStateRecovery.startingCodexPlaceholderText
        )
        let assistantContinued = PersistedChatMessage(role: .assistant, text: "Still working...")
        let assistantWorking = PersistedChatMessage(role: .assistant, text: "Working (42s • esc to interrupt)")
        let userMessage = PersistedChatMessage(role: .user, text: "hello")

        let result = ChatBusyStateRecovery.normalizedMessagesForAppRelaunch(
            [assistantThinking, assistantStartingCodex, assistantContinued, assistantWorking, userMessage]
        )

        #expect(result.didMutate)
        #expect(result.messages[0].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.messages[1].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.messages[2].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.messages[3].text == ChatBusyStateRecovery.cancelledPlaceholderText)
        #expect(result.messages[4].text == "hello")
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
        let loadingThree = PersistedChatMessage(role: .assistant, text: "Still working...")
        let cancelled = PersistedChatMessage(role: .assistant, text: ChatBusyStateRecovery.cancelledPlaceholderText)

        let result = ChatBusyStateRecovery.normalizedMessagesForNewRequest(
            [userOne, loadingOne, assistantDone, loadingTwo, loadingThree, cancelled]
        )

        #expect(result.didMutate)
        #expect(result.messages == [userOne, assistantDone, cancelled])
    }
}

@Suite("Chat final assistant message reconciliation")
struct ChatFinalAssistantMessageReconcilerTests {
    @Test("appends final text when no streamed message rendered")
    func appendsFinalText() {
        let user = PersistedChatMessage(role: .user, text: "hello")

        let result = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
            [user],
            streamedMessageIDs: [],
            finalText: "final answer",
            modelId: "gpt-5.5",
            reasoningLevel: "low"
        )

        #expect(result.didMutate)
        #expect(result.messages.map(\.role) == [.user, .assistant])
        #expect(result.messages.last?.text == "final answer")
        #expect(result.messages.last?.modelId == "gpt-5.5")
        #expect(result.messages.last?.reasoningLevel == "low")
    }

    @Test("replaces partial streamed message with final text")
    func replacesPartialStreamedText() {
        let user = PersistedChatMessage(role: .user, text: "hello")
        let streamed = PersistedChatMessage(role: .assistant, text: "first update")

        let result = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
            [user, streamed],
            streamedMessageIDs: [streamed.id],
            finalText: "first update\n\nfinal answer",
            modelId: "gpt-5.5",
            reasoningLevel: "medium"
        )

        #expect(result.didMutate)
        #expect(result.messages.count == 2)
        #expect(result.messages[1].id == streamed.id)
        #expect(result.messages[1].text == "first update\n\nfinal answer")
        #expect(result.messages[1].modelId == "gpt-5.5")
        #expect(result.messages[1].reasoningLevel == "medium")
    }

    @Test("leaves completed streamed aggregate items separate")
    func leavesCompletedStreamedAggregateItemsSeparate() {
        let first = PersistedChatMessage(role: .assistant, text: "commentary")
        let second = PersistedChatMessage(role: .assistant, text: "final")

        let result = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
            [first, second],
            streamedMessageIDs: [first.id, second.id],
            finalText: "commentary\n\nfinal",
            modelId: nil,
            reasoningLevel: nil
        )

        #expect(!result.didMutate)
        #expect(result.messages.count == 2)
        #expect(result.messages[0].id == first.id)
        #expect(result.messages[0].text == "commentary")
        #expect(result.messages[1].id == second.id)
        #expect(result.messages[1].text == "final")
    }

    @Test("appends final text after multiple partial streamed items")
    func appendsFinalTextAfterMultiplePartialStreamedItems() {
        let first = PersistedChatMessage(role: .assistant, text: "I’ll inspect.")
        let second = PersistedChatMessage(role: .assistant, text: "Tool output:\nfound")

        let result = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
            [first, second],
            streamedMessageIDs: [first.id, second.id],
            finalText: "Done.",
            modelId: nil,
            reasoningLevel: nil
        )

        #expect(result.didMutate)
        #expect(result.messages.count == 3)
        #expect(result.messages[0].id == first.id)
        #expect(result.messages[1].id == second.id)
        #expect(result.messages[2].text == "Done.")
    }

    @Test("appends structured tool event for final tool transcript")
    func appendsStructuredToolEventForFinalToolTranscript() {
        let user = PersistedChatMessage(role: .user, text: "run tests")
        let finalText = ChatToolTranscriptFormatter.toolResultText(
            name: "exec_command",
            arguments: "{\"cmd\":\"swift test\"}",
            output: "passed"
        )

        let result = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
            [user],
            streamedMessageIDs: [],
            finalText: finalText,
            modelId: nil,
            reasoningLevel: nil
        )

        #expect(result.didMutate)
        #expect(result.messages.last?.toolEvent?.kind == .result)
        #expect(result.messages.last?.toolEvent?.name == "exec_command")
        #expect(result.messages.last?.toolEvent?.output == "passed")
    }

    @Test("updates streamed message with structured tool event for final tool transcript")
    func updatesStreamedMessageWithStructuredToolEventForFinalToolTranscript() {
        let streamed = PersistedChatMessage(role: .assistant, text: "running")
        let finalText = ChatToolTranscriptFormatter.toolOutputText("done", name: "exec_command")

        let result = ChatFinalAssistantMessageReconciler.messagesByReconcilingFinalAssistantText(
            [streamed],
            streamedMessageIDs: [streamed.id],
            finalText: finalText,
            modelId: nil,
            reasoningLevel: nil
        )

        #expect(result.didMutate)
        #expect(result.messages.count == 1)
        #expect(result.messages[0].id == streamed.id)
        #expect(result.messages[0].toolEvent?.kind == .output)
        #expect(result.messages[0].toolEvent?.outputName == "exec_command")
        #expect(result.messages[0].toolEvent?.output == "done")
    }
}
