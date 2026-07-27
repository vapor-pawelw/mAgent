import Foundation
import MagentCore
import Testing

@Suite
struct TerminalTabMigrationTests {
    @Test
    func capturesAndInstallsUserVisibleTabState() throws {
        let sourceSession = "ma-project-main-codex"
        var source = MagentThread(
            projectId: UUID(),
            name: "main",
            worktreePath: "/repo",
            branchName: "main",
            tmuxSessionNames: [sourceSession],
            agentTmuxSessions: [sourceSession],
            sessionConversationIDs: [sourceSession: "conversation-1"],
            sessionAgentTypes: [sourceSession: .codex],
            pinnedTmuxSessions: [sourceSession],
            customTabNames: [sourceSession: "Large refactor"],
            manuallyRenamedTabs: [sourceSession],
            submittedPromptsBySession: [sourceSession: ["Refactor the persistence layer"]]
        )
        source.isKeepAlive = true
        source.forwardedTmuxSessions.insert(sourceSession)
        source.unreadCompletionSessions.insert(sourceSession)
        source.unreadRateLimitSessions.insert(sourceSession)

        let migration = try #require(source.terminalTabMigration(for: sourceSession))
        var destination = MagentThread(
            projectId: source.projectId,
            name: "destination",
            worktreePath: "/worktrees/destination",
            branchName: "destination",
            tmuxSessionNames: []
        )
        let createdAt = Date()
        destination.installMigratedTerminalTab(
            migration,
            sessionName: "ma-project-destination-large-refactor",
            createdAt: createdAt
        )

        let destinationSession = try #require(destination.tmuxSessionNames.first)
        #expect(destination.displayName(for: destinationSession, at: 0) == "Large refactor")
        #expect(destination.sessionConversationIDs[destinationSession] == "conversation-1")
        #expect(destination.sessionAgentTypes[destinationSession] == .codex)
        #expect(destination.sessionCreatedAts[destinationSession] == createdAt)
        #expect(destination.manuallyRenamedTabs.contains(destinationSession))
        #expect(destination.forwardedTmuxSessions.contains(destinationSession))
        #expect(destination.pinnedTmuxSessions == [destinationSession])
        #expect(destination.protectedTmuxSessions.contains(destinationSession))
        #expect(destination.unreadCompletionSessions.contains(destinationSession))
        #expect(destination.unreadRateLimitSessions.contains(destinationSession))
        #expect(destination.submittedPromptsBySession[destinationSession] == ["Refactor the persistence layer"])

        var pending = MagentThread(
            id: destination.id,
            projectId: destination.projectId,
            name: destination.name,
            worktreePath: destination.worktreePath,
            branchName: destination.branchName,
            tmuxSessionNames: []
        )
        pending.mergePhase2Setup(from: destination)
        #expect(pending.sessionConversationIDs[destinationSession] == "conversation-1")
        #expect(pending.customTabNames[destinationSession] == "Large refactor")
        #expect(pending.manuallyRenamedTabs.contains(destinationSession))
        #expect(pending.pinnedTmuxSessions == [destinationSession])
        #expect(pending.protectedTmuxSessions.contains(destinationSession))
        #expect(pending.unreadCompletionSessions.contains(destinationSession))
        #expect(pending.unreadRateLimitSessions.contains(destinationSession))
    }

    @Test
    func removalClearsSessionStateAndSelectsRemainingTab() {
        let movedSession = "ma-project-thread-codex"
        let remainingSession = "ma-project-thread-claude"
        var thread = MagentThread(
            projectId: UUID(),
            name: "thread",
            worktreePath: "/worktrees/thread",
            branchName: "thread",
            tmuxSessionNames: [movedSession, remainingSession],
            agentTmuxSessions: [movedSession, remainingSession],
            sessionConversationIDs: [movedSession: "conversation"],
            sessionAgentTypes: [movedSession: .codex, remainingSession: .claude],
            lastSelectedTabIdentifier: movedSession,
            customTabNames: [movedSession: "Move me"],
            manuallyRenamedTabs: [movedSession],
            submittedPromptsBySession: [movedSession: ["Prompt"]]
        )
        thread.busySessions.insert(movedSession)
        thread.waitingForInputSessions.insert(movedSession)

        thread.removeMigratedTerminalTab(sessionName: movedSession)

        #expect(thread.tmuxSessionNames == [remainingSession])
        #expect(thread.lastSelectedTabIdentifier == remainingSession)
        #expect(!thread.agentTmuxSessions.contains(movedSession))
        #expect(thread.sessionConversationIDs[movedSession] == nil)
        #expect(thread.sessionAgentTypes[movedSession] == nil)
        #expect(thread.customTabNames[movedSession] == nil)
        #expect(!thread.manuallyRenamedTabs.contains(movedSession))
        #expect(thread.submittedPromptsBySession[movedSession] == nil)
        #expect(!thread.busySessions.contains(movedSession))
        #expect(!thread.waitingForInputSessions.contains(movedSession))
    }

    @Test
    func migrationRequiresDeterministicConversationResume() {
        let session = "ma-project-thread-terminal"
        let terminal = MagentThread(
            projectId: UUID(),
            name: "thread",
            worktreePath: "/worktrees/thread",
            branchName: "thread",
            tmuxSessionNames: [session]
        )
        #expect(terminal.terminalTabMigration(for: session) == nil)

        var customAgent = terminal
        customAgent.agentTmuxSessions = [session]
        customAgent.sessionAgentTypes = [session: .custom]
        customAgent.sessionConversationIDs = [session: "custom-conversation"]
        #expect(customAgent.terminalTabMigration(for: session) == nil)
    }

    @Test
    func recoveryOnlyOffersRetryForRedundantStashCleanup() {
        #expect(
            TabMoveRecoveryFailureStage.redundantStashCleanup.retryScope
                == .redundantStashCleanup
        )
        #expect(TabMoveRecoveryFailureStage.recoveryScan.retryScope == nil)
        #expect(TabMoveRecoveryFailureStage.sourceThreadUnavailable.retryScope == nil)
        #expect(TabMoveRecoveryFailureStage.sourceWorktreeInspection.retryScope == nil)
        #expect(TabMoveRecoveryFailureStage.sourceWorktreeChanged.retryScope == nil)
        #expect(TabMoveRecoveryFailureStage.destinationCleanup.retryScope == nil)
        #expect(TabMoveRecoveryFailureStage.sourceRestore.retryScope == nil)

        #expect(
            TabMoveRecoveryBannerPolicy(
                stages: [.redundantStashCleanup, .redundantStashCleanup]
            ).retryScope == .redundantStashCleanup
        )
        #expect(
            TabMoveRecoveryBannerPolicy(
                stages: [.sourceWorktreeChanged, .redundantStashCleanup]
            ).retryScope == nil
        )
    }
}
