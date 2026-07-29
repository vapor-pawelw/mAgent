import Foundation
import MagentModels
import Testing
@testable import UtilityCore

@Suite("Codex chat functional regressions")
struct CodexChatFunctionalRegressionTests {
    @Test(
        "Fallback only replays prompts that did not start",
        arguments: [
            (
                CodexAppServerPromptReplaySafety.safeBeforeTurn,
                "Codex app-server failed: process could not launch",
                true
            ),
            (
                CodexAppServerPromptReplaySafety.unsafeAfterTurnStarted,
                "Codex app-server failed: turn failed",
                false
            ),
            (
                CodexAppServerPromptReplaySafety.unsafeAfterTurnStarted,
                "Codex app-server failed: Blocked: Codex requested approval.",
                false
            ),
            (
                CodexAppServerPromptReplaySafety.unsafeAfterTurnStarted,
                "No response from Codex.",
                false
            ),
        ]
    )
    func fallbackRespectsReplaySafety(
        replaySafety: CodexAppServerPromptReplaySafety,
        text: String,
        expectedFallback: Bool
    ) {
        let attempt = CodexAppServerAttempt(
            result: AgentChatExecutionResult(
                assistantText: text,
                conversationSessionID: "thread-1"
            ),
            replaySafety: replaySafety
        )

        #expect(CodexAppServerFallbackPolicy.shouldFallbackToExec(attempt) == expectedFallback)
    }

    @Test("Steering submitted during a completion race remains available for the next turn")
    func steerChannelDrainsUnsentInput() {
        let channel = AgentChatSteerChannel()
        let first = AgentChatSteerInput(text: "check the tests too")
        let second = AgentChatSteerInput(text: "then summarize")

        #expect(channel.submit(first))
        #expect(channel.submit(second))
        #expect(channel.popFirst() == first)
        channel.acknowledge(id: first.id)
        #expect(channel.popFirst() == second)
        #expect(channel.closeAndDrain() == [second])
        #expect(!channel.submit(AgentChatSteerInput(text: "too late")))
    }

    @Test("Destructive cancellation discards every queued prompt")
    func destructiveCancellationDiscardsQueue() {
        let transition = ChatPromptQueuePolicy.transitionAfterCancellation(
            queuedPrompts: ["first queued", "second queued"],
            behavior: .discardQueuedPrompts
        )

        #expect(transition.nextPrompt == nil)
        #expect(transition.remainingPrompts.isEmpty)
    }

    @Test("Interactive cancellation advances exactly one queued prompt")
    func interactiveCancellationAdvancesQueue() {
        let transition = ChatPromptQueuePolicy.transitionAfterCancellation(
            queuedPrompts: ["first queued", "second queued"],
            behavior: .continueWithNextPrompt
        )

        #expect(transition.nextPrompt == "first queued")
        #expect(transition.remainingPrompts == ["second queued"])
    }

    @Test("Effort help reflects every level supported by the selected Codex model")
    func effortHelpIncludesLatestLevels() {
        let usage = AgentChatHelpCommandBuilder.effortUsage(
            reasoningLevels: ["none", "low", "medium", "high", "xhigh", "max", "ultra"]
        )

        #expect(usage == "/effort <none|low|medium|high|xhigh|max|ultra>")
    }

    @Test("Message origin remains backward compatible and persists local UI markers")
    func messageOriginPersistence() throws {
        let legacyData = try #require(#"{"role":"assistant","text":"legacy"}"#.data(using: .utf8))
        let legacyMessage = try JSONDecoder().decode(PersistedChatMessage.self, from: legacyData)
        #expect(legacyMessage.origin == .agentTranscript)

        let localMessage = PersistedChatMessage(
            role: .assistant,
            text: "Available slash commands:",
            origin: .localUI
        )
        let restoredLocalMessage = try JSONDecoder().decode(
            PersistedChatMessage.self,
            from: JSONEncoder().encode(localMessage)
        )
        #expect(restoredLocalMessage.origin == .localUI)
    }

    @Test("Transcript restore keeps local markers and slash-command output")
    func restoreKeepsLocalMessages() {
        let firstUser = PersistedChatMessage(role: .user, text: "first")
        let firstAssistant = PersistedChatMessage(role: .assistant, text: "First reply")
        let modelNotice = PersistedChatMessage(
            role: .system,
            text: "Model changed to GPT 5.6 Sol (high)",
            origin: .localUI
        )
        let secondUser = PersistedChatMessage(role: .user, text: "second")
        let help = PersistedChatMessage(
            role: .assistant,
            text: "Available slash commands:\n• /help",
            origin: .localUI
        )
        let jsonl = """
        {"timestamp":"2026-05-22T08:00:00Z","type":"event_msg","payload":{"type":"user_message","message":"first"}}
        {"timestamp":"2026-05-22T08:00:01Z","type":"event_msg","payload":{"type":"agent_message","message":"First reply"}}
        {"timestamp":"2026-05-22T08:20:00Z","type":"event_msg","payload":{"type":"user_message","message":"second"}}
        {"timestamp":"2026-05-22T08:20:01Z","type":"event_msg","payload":{"type":"agent_message","message":"Second reply"}}
        {"timestamp":"2026-05-22T08:20:02Z","type":"event_msg","payload":{"type":"task_complete"}}
        """

        let restored = CodexChatTranscriptReconciler.messages(
            fromCodexJSONL: jsonl,
            existingMessages: [firstUser, firstAssistant, modelNotice, secondUser, help]
        )

        #expect(restored.contains(where: { $0.id == modelNotice.id }))
        #expect(restored.contains(where: { $0.id == help.id }))
        #expect(restored.map(\.text).contains("Second reply"))
    }

    @Test("Repeated prompts retain distinct identities and metadata")
    func repeatedPromptsKeepOccurrenceIdentity() throws {
        let firstDate = Date(timeIntervalSince1970: 1_000)
        let secondDate = Date(timeIntervalSince1970: 2_000)
        let firstUser = PersistedChatMessage(
            role: .user,
            text: "repeat this",
            createdAt: firstDate,
            modelId: "gpt-first"
        )
        let secondUser = PersistedChatMessage(
            role: .user,
            text: "repeat this",
            createdAt: secondDate,
            modelId: "gpt-second"
        )
        let jsonl = """
        {"timestamp":"2026-05-22T08:00:00Z","type":"event_msg","payload":{"type":"user_message","message":"repeat this"}}
        {"timestamp":"2026-05-22T08:00:01Z","type":"event_msg","payload":{"type":"agent_message","message":"First reply"}}
        {"timestamp":"2026-05-22T08:20:00Z","type":"event_msg","payload":{"type":"user_message","message":"repeat this"}}
        {"timestamp":"2026-05-22T08:20:01Z","type":"event_msg","payload":{"type":"agent_message","message":"Second reply"}}
        {"timestamp":"2026-05-22T08:20:02Z","type":"event_msg","payload":{"type":"task_complete"}}
        """

        let restored = CodexChatTranscriptReconciler.messages(
            fromCodexJSONL: jsonl,
            existingMessages: [firstUser, secondUser]
        )
        let users = restored.filter { $0.role == .user }
        #expect(users.count == 2)
        let firstRestored = try #require(users.first)
        let secondRestored = try #require(users.last)
        #expect(firstRestored.id == firstUser.id)
        #expect(secondRestored.id == secondUser.id)
        #expect(firstRestored.id != secondRestored.id)
        #expect(firstRestored.createdAt == firstDate)
        #expect(secondRestored.createdAt == secondDate)
        #expect(firstRestored.modelId == "gpt-first")
        #expect(secondRestored.modelId == "gpt-second")
    }
}
