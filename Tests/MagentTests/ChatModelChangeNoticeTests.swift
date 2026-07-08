import Foundation
import MagentCore
import Testing

@Suite("Chat model change notices")
struct ChatModelChangeNoticeTests {
    @Test("does not inject before first user message")
    func doesNotInjectBeforeFirstUserMessage() {
        let messages: [PersistedChatMessage] = []
        let updated = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
            into: messages,
            nextModelName: "GPT-5",
            nextModelId: "gpt-5",
            nextReasoningLevel: "high"
        )

        #expect(updated.isEmpty)
    }

    @Test("injects notice before next user message when model changes")
    func injectsWhenModelChanges() {
        let previous = PersistedChatMessage(role: .user, text: "hello", modelId: "gpt-5", reasoningLevel: "medium")
        let updated = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
            into: [previous],
            nextModelName: "GPT-5.1",
            nextModelId: "gpt-5.1",
            nextReasoningLevel: "medium"
        )

        #expect(updated.count == 2)
        #expect(updated[1].role == .system)
        #expect(updated[1].text == "Model changed to GPT-5.1 (medium)")
    }

    @Test("injects notice when only reasoning changes")
    func injectsWhenReasoningChanges() {
        let previous = PersistedChatMessage(role: .user, text: "hello", modelId: "gpt-5", reasoningLevel: "low")
        let updated = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
            into: [previous],
            nextModelName: "GPT-5",
            nextModelId: "gpt-5",
            nextReasoningLevel: "high"
        )

        #expect(updated.map(\.role) == [.user, .system])
        #expect(updated[1].text == "Model changed to GPT-5 (high)")
    }

    @Test("renders none reasoning as fast")
    func rendersNoneReasoningAsFast() {
        let previous = PersistedChatMessage(role: .user, text: "hello", modelId: "gpt-5", reasoningLevel: "high")
        let updated = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
            into: [previous],
            nextModelName: "GPT-5",
            nextModelId: "gpt-5",
            nextReasoningLevel: "none"
        )

        #expect(updated.map(\.role) == [.user, .system])
        #expect(updated[1].text == "Model changed to GPT-5 (fast)")
    }

    @Test("does not inject duplicate notice for unchanged metadata")
    func skipsWhenUnchanged() {
        let previous = PersistedChatMessage(role: .user, text: "hello", modelId: "gpt-5", reasoningLevel: "medium")
        let assistant = PersistedChatMessage(role: .assistant, text: "done", modelId: "gpt-5", reasoningLevel: "medium")
        let updated = ChatModelChangeNotice.messagesByInjectingNoticeIfNeeded(
            into: [previous, assistant],
            nextModelName: "GPT-5",
            nextModelId: "gpt-5",
            nextReasoningLevel: "medium"
        )

        #expect(updated == [previous, assistant])
    }

    @Test("persists system notice messages in chat tab codable payloads")
    func persistsSystemNoticeMessages() throws {
        let notice = PersistedChatMessage(
            role: .system,
            text: "Model changed to GPT-5.1 (high)",
            modelId: "gpt-5.1",
            reasoningLevel: "high"
        )
        let tab = PersistedChatTab(
            identifier: "chat:notice",
            agentType: .codex,
            title: "Chat",
            messages: [
                PersistedChatMessage(role: .user, text: "before", modelId: "gpt-5", reasoningLevel: "medium"),
                notice,
                PersistedChatMessage(role: .user, text: "after", modelId: "gpt-5.1", reasoningLevel: "high"),
            ]
        )

        let data = try JSONEncoder().encode(tab)
        let decoded = try JSONDecoder().decode(PersistedChatTab.self, from: data)

        #expect(decoded.messages.map(\.role) == [.user, .system, .user])
        #expect(decoded.messages[1].text == notice.text)
        #expect(decoded.messages[1].modelId == "gpt-5.1")
        #expect(decoded.messages[1].reasoningLevel == "high")
    }

}
