import AppKit
import Foundation
import MagentCore

extension ThreadManager {
    @discardableResult
    func moveTerminalTabToNewThread(
        sourceThreadID: UUID,
        sessionName: String
    ) async throws -> MagentThread {
        try await tabMigrationOperationGate.withExclusiveAccess {
            try await performTerminalTabMoveToNewThread(
                sourceThreadID: sourceThreadID,
                sessionName: sessionName
            )
        }
    }

    private func performTerminalTabMoveToNewThread(
        sourceThreadID: UUID,
        sessionName: String
    ) async throws -> MagentThread {
        await syncBusySessionsFromProcessState()
        guard let sourceThread = store.thread(byId: sourceThreadID) else {
            throw ThreadManagerError.threadNotFound
        }
        guard !sourceThread.busySessions.contains(sessionName),
              !sourceThread.magentBusySessions.contains(sessionName),
              !sourceThread.waitingForInputSessions.contains(sessionName),
              !sourceThread.hasUnsubmittedInputSessions.contains(sessionName) else {
            throw ThreadManagerError.tabMoveRequiresIdleAgent
        }
        guard let migration = sourceThread.terminalTabMigration(for: sessionName) else {
            throw ThreadManagerError.tabMoveRequiresResumableAgent
        }

        let settings = persistence.loadSettings()
        guard let project = settings.projects.first(where: { $0.id == sourceThread.projectId }) else {
            throw ThreadManagerError.projectNotFound
        }
        let sourceBranch = sourceThread.actualBranch?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expectedBranch = sourceThread.branchName
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let baseBranch: String?
        if sourceBranch == "HEAD" {
            guard let sourceCommit = await git.currentCommit(worktreePath: sourceThread.worktreePath) else {
                throw ThreadManagerError.noExpectedBranch
            }
            baseBranch = sourceCommit
        } else if let sourceBranch, !sourceBranch.isEmpty {
            baseBranch = sourceBranch
        } else if !expectedBranch.isEmpty {
            baseBranch = expectedBranch
        } else {
            baseBranch = project.defaultBranch
        }

        let created = try await createThread(
            project: project,
            requestedAgentType: migration.agentType,
            useAgentCommand: true,
            requestedBaseBranch: baseBranch,
            requestedSectionId: sourceThread.sectionId,
            insertAfterThreadId: sourceThread.sidebarListState == .visible ? sourceThread.id : nil,
            insertAtTopOfVisibleGroup: sourceThread.sidebarListState == .pinned,
            localFileSyncEntriesOverride: sourceThread.localFileSyncEntriesSnapshot,
            terminalTabMigration: migration,
            moveChangesFromWorktreePath: sourceThread.worktreePath
        )

        guard let createdSessionName = created.tmuxSessionNames.first,
              await waitForAgentPrompt(
                  sessionName: createdSessionName,
                  agentType: migration.agentType,
                  timeout: 30
              ) else {
            try await rollbackCreatedThreadAfterFailedTabMove(created, sourceThreadID: sourceThreadID)
            throw ThreadManagerError.tabMoveResumeFailed
        }

        do {
            try await removeSourceTabAfterMigration(
                sourceThreadID: sourceThreadID,
                sessionName: sessionName
            )
            await threadLifecycleService.finishTabMoveChangeTransfer(for: created.id)
        } catch let moveError {
            do {
                try await rollbackCreatedThreadAfterFailedTabMove(
                    created,
                    sourceThreadID: sourceThreadID
                )
            } catch {
                throw GitError.commandFailed(
                    """
                    The tab move failed and automatic recovery was incomplete. \
                    \(error.localizedDescription) Original error: \(moveError.localizedDescription)
                    """
                )
            }
            throw moveError
        }
        _ = await refreshDirtyState(for: sourceThreadID)
        _ = await refreshDirtyState(for: created.id)

        if let newSessionName = created.tmuxSessionNames.first,
           let lastPrompt = migration.submittedPrompts.last,
           !lastPrompt.isEmpty {
            Task { [weak self] in
                _ = await self?.autoRenameThreadAfterFirstPromptIfNeeded(
                    threadId: created.id,
                    sessionName: newSessionName,
                    prompt: lastPrompt
                )
            }
        }

        return store.thread(byId: created.id) ?? created
    }

    private func rollbackCreatedThreadAfterFailedTabMove(
        _ created: MagentThread,
        sourceThreadID: UUID
    ) async throws {
        var deletionError: Error?
        do {
            try await deleteThread(created)
        } catch {
            deletionError = error
        }
        try await threadLifecycleService.rollbackTabMoveChangeTransfer(for: created.id)
        _ = await refreshDirtyState(for: sourceThreadID)
        if let deletionError {
            throw deletionError
        }
    }

    @MainActor
    private func removeSourceTabAfterMigration(
        sourceThreadID: UUID,
        sessionName: String
    ) async throws {
        guard let sourceBeforeRemoval = store.thread(byId: sourceThreadID),
              store.update(id: sourceThreadID, { thread in
                  thread.removeMigratedTerminalTab(sessionName: sessionName)
              }) else {
            throw ThreadManagerError.threadNotFound
        }
        do {
            try persistence.saveActiveThreads(store.threads)
        } catch {
            _ = store.update(id: sourceThreadID) { thread in
                thread = sourceBeforeRemoval
            }
            throw error
        }

        if PopoutWindowManager.shared.isTabDetached(sessionName: sessionName) {
            PopoutWindowManager.shared.returnTabToThread(sessionName: sessionName)
        }
        NotificationCenter.default.post(
            name: .magentTabWillClose,
            object: nil,
            userInfo: ["threadId": sourceThreadID, "sessionName": sessionName]
        )
        ReusableTerminalViewCache.shared.evictSessions([sessionName])
        try? await tmux.killSession(name: sessionName)

        sessionLastVisitedAt.removeValue(forKey: sessionName)
        sessionLastBusyAt.removeValue(forKey: sessionName)
        notifiedWaitingSessions.remove(sessionName)
        rateLimitLiftPendingResumeSessions.remove(sessionName)
        lastRuntimeDetectedAgentBySession.removeValue(forKey: sessionName)
        rendererUnhealthySessions.remove(sessionName)
        replayCorruptedSessions.remove(sessionName)
        evictedIdleSessions.remove(sessionName)
        clearTrackedInitialPromptInjection(for: sessionName)

        delegate?.threadManager(self, didUpdateThreads: store.threads)
    }
}
