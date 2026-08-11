import Foundation
import MagentCore
import Testing

@MainActor
@Suite("Chat prompt coordination")
struct ChatPromptCoordinatorTests {
    @Test("GUI and IPC cannot start overlapping turns for one chat")
    func rejectsASecondClient() {
        let coordinator = ChatPromptCoordinator()
        let key = UUID().uuidString
        let first = coordinator.prepareSubmission(
            key: key,
            client: .gui,
            agentType: .codex,
            prompt: "first",
            messageID: UUID(),
            allowsSteering: true
        )
        guard case .start(let requestID, _) = first else {
            Issue.record("The first prompt did not reserve the chat")
            return
        }

        let overlapping = coordinator.prepareSubmission(
            key: key,
            client: .ipc,
            agentType: .codex,
            prompt: "second",
            messageID: UUID(),
            allowsSteering: true
        )
        guard case .busy = overlapping else {
            Issue.record("A second client was allowed to overlap the active turn")
            return
        }

        coordinator.finishRequest(key: key, requestID: requestID)
        let afterCompletion = coordinator.prepareSubmission(
            key: key,
            client: .ipc,
            agentType: .codex,
            prompt: "second",
            messageID: UUID(),
            allowsSteering: true
        )
        guard case .start = afterCompletion else {
            Issue.record("The chat remained locked after its active turn completed")
            return
        }
    }

    @Test("A stale completion cannot release a newer reservation")
    func staleCompletionDoesNotUnlockNewerTurn() {
        let coordinator = ChatPromptCoordinator()
        let key = UUID().uuidString
        let first = coordinator.prepareSubmission(
            key: key,
            client: .gui,
            agentType: .claude,
            prompt: "first",
            messageID: UUID(),
            allowsSteering: false
        )
        guard case .start(let firstID, _) = first else { return }
        coordinator.finishRequest(key: key, requestID: firstID)

        let second = coordinator.prepareSubmission(
            key: key,
            client: .ipc,
            agentType: .claude,
            prompt: "second",
            messageID: UUID(),
            allowsSteering: false
        )
        guard case .start = second else { return }
        coordinator.finishRequest(key: key, requestID: firstID)

        let overlapping = coordinator.prepareSubmission(
            key: key,
            client: .gui,
            agentType: .claude,
            prompt: "third",
            messageID: UUID(),
            allowsSteering: false
        )
        guard case .busy = overlapping else {
            Issue.record("A stale completion released the newer request")
            return
        }
    }
}
