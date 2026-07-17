import Foundation
import MagentCore
import Testing

@Suite("Chat persistence scheduling")
struct ChatPersistenceScheduleTests {
    @Test("Draft changes extend one worker's trailing deadline")
    func draftChangesExtendTrailingDeadline() {
        var state = ChatPersistenceScheduleState(draftDebounceInterval: 0.5)
        let start = Date(timeIntervalSince1970: 1_000)

        let startsWorker = state.recordDraftChange(identifier: "chat", now: start)
        let startsSecondWorker = state.recordDraftChange(identifier: "chat", now: start.addingTimeInterval(0.3))
        let actionBeforeDeadline = state.draftAction(identifier: "chat", now: start.addingTimeInterval(0.6))
        let actionAtDeadline = state.draftAction(identifier: "chat", now: start.addingTimeInterval(0.8))
        let actionAfterPersist = state.draftAction(identifier: "chat", now: start.addingTimeInterval(1))

        #expect(startsWorker)
        #expect(!startsSecondWorker)
        #expect(actionBeforeDeadline == .wait(until: start.addingTimeInterval(0.8)))
        #expect(actionAtDeadline == .persist)
        #expect(actionAfterPersist == nil)
    }

    @Test("Independent chat drafts debounce independently")
    func independentDrafts() {
        var state = ChatPersistenceScheduleState(draftDebounceInterval: 0.5)
        let start = Date(timeIntervalSince1970: 2_000)

        let startsFirstWorker = state.recordDraftChange(identifier: "first", now: start)
        let startsSecondWorker = state.recordDraftChange(identifier: "second", now: start.addingTimeInterval(0.2))
        let firstAction = state.draftAction(identifier: "first", now: start.addingTimeInterval(0.5))
        let secondAction = state.draftAction(identifier: "second", now: start.addingTimeInterval(0.5))

        #expect(startsFirstWorker)
        #expect(startsSecondWorker)
        #expect(firstAction == .persist)
        #expect(secondAction == .wait(until: start.addingTimeInterval(0.7)))
    }

    @Test("Continuous streams use a bounded periodic checkpoint interval")
    func streamCheckpointInterval() {
        let state = ChatPersistenceScheduleState(streamCheckpointInterval: 1.25)
        #expect(state.streamCheckpointInterval == 1.25)
    }

    @Test("Chat persistence updates only the selected thread")
    func chatPersistencePreservesOtherThreadState() {
        var selected = MagentThread(
            projectId: UUID(),
            name: "selected",
            worktreePath: "/tmp/selected",
            branchName: "selected"
        )
        selected.taskDescription = "newer non-chat state"
        let other = MagentThread(
            projectId: UUID(),
            name: "other",
            worktreePath: "/tmp/other",
            branchName: "other"
        )
        let tab = PersistedChatTab(identifier: "chat", agentType: .codex, title: "Chat")

        let result = PersistenceService.applyingChatTabs([tab], for: selected.id, to: [selected, other])

        #expect(result.didUpdate)
        #expect(result.threads[0].persistedChatTabs == [tab])
        #expect(result.threads[0].taskDescription == "newer non-chat state")
        #expect(result.threads[1] == other)
    }

    @Test("Older chat persistence revisions are discarded when tasks arrive out of order")
    func persistenceRevisionOrdering() {
        var gate = ChatPersistenceRevisionGate()
        let threadID = UUID()

        let acceptsNewest = gate.accepts(threadID: threadID, revision: 2)
        let newestIsCurrentBeforeInterleaving = gate.isCurrent(threadID: threadID, revision: 2)
        let acceptsOlder = gate.accepts(threadID: threadID, revision: 1)
        let acceptsDuplicate = gate.accepts(threadID: threadID, revision: 2)
        let acceptsNext = gate.accepts(threadID: threadID, revision: 3)
        let retryOfSupersededRevisionIsCurrent = gate.isCurrent(threadID: threadID, revision: 2)
        let acceptsOtherThread = gate.accepts(threadID: UUID(), revision: 1)

        #expect(acceptsNewest)
        #expect(newestIsCurrentBeforeInterleaving)
        #expect(!acceptsOlder)
        #expect(!acceptsDuplicate)
        #expect(acceptsNext)
        #expect(!retryOfSupersededRevisionIsCurrent)
        #expect(acceptsOtherThread)
    }
}
