import Foundation
import Testing
import MagentCore

@Suite("Persistence chat-tabs sidecar recovery")
struct PersistenceChatTabsRecoveryTests {

    @Test("Recovers missing chat tabs from sidecar")
    func recoversMissingChatTabs() {
        let threadWithMissingTabs = makeThread(name: "one", chatTabs: [])
        let untouchedThread = makeThread(name: "two", chatTabs: [])

        let recoveredTab = PersistedChatTab(
            identifier: "chat:recovered",
            agentType: .codex,
            title: "Recovered chat",
            messages: [PersistedChatMessage(role: .assistant, text: "hello")]
        )
        let sidecar: [String: [PersistedChatTab]] = [
            threadWithMissingTabs.id.uuidString: [recoveredTab],
        ]

        let result = PersistenceService.applyChatTabsSidecarRecovery(
            to: [threadWithMissingTabs, untouchedThread],
            sidecar: sidecar
        )

        #expect(result[0].persistedChatTabs == [recoveredTab])
        #expect(result[1].persistedChatTabs.isEmpty)
    }

    @Test("Does not overwrite existing chat tabs with sidecar")
    func doesNotOverwriteExistingChatTabs() {
        let existingTab = PersistedChatTab(
            identifier: "chat:existing",
            agentType: .claude,
            title: "Existing",
            messages: [PersistedChatMessage(role: .assistant, text: "keep me")]
        )
        let thread = makeThread(name: "one", chatTabs: [existingTab])

        let staleTab = PersistedChatTab(
            identifier: "chat:stale",
            agentType: .codex,
            title: "Stale",
            messages: [PersistedChatMessage(role: .assistant, text: "old")]
        )
        let sidecar: [String: [PersistedChatTab]] = [
            thread.id.uuidString: [staleTab],
        ]

        let result = PersistenceService.applyChatTabsSidecarRecovery(
            to: [thread],
            sidecar: sidecar
        )

        #expect(result[0].persistedChatTabs == [existingTab])
    }

    private func makeThread(name: String, chatTabs: [PersistedChatTab]) -> MagentThread {
        MagentThread(
            projectId: UUID(),
            name: name,
            worktreePath: "/tmp/\(name)",
            branchName: "branch-\(name)",
            persistedChatTabs: chatTabs
        )
    }
}
