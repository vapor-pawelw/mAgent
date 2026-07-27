import AppKit
import Foundation
import UserNotifications
import MagentCore

@MainActor
protocol ThreadManagerDelegate: AnyObject {
    func threadManager(_ manager: ThreadManager, didCreateThread thread: MagentThread)
    func threadManager(_ manager: ThreadManager, didArchiveThread thread: MagentThread)
    func threadManager(_ manager: ThreadManager, didDeleteThread thread: MagentThread)
    func threadManager(_ manager: ThreadManager, didUpdateThreads threads: [MagentThread])
}

final class ThreadManager {
    static let maxFavoriteThreadCount = 10

    struct StatusSyncResult {
        let hadErrors: Bool
        let failureSummary: String?

        static let success = StatusSyncResult(hadErrors: false, failureSummary: nil)

        static func failure(_ summary: String?) -> StatusSyncResult {
            StatusSyncResult(hadErrors: true, failureSummary: summary)
        }
    }

    struct InitialPromptInjectionFailureInfo {
        let prompt: String
        let shouldSubmitInitialPrompt: Bool
        let agentType: AgentType?
        let requiresAgentRelaunch: Bool
    }

    struct BaseBranchReset: Sendable {
        let oldBase: String
        let newBase: String
    }

    struct PendingPromptRecoveryInfo {
        let tempFileURL: URL
        let prompt: String
        let agentType: AgentType?
        let projectId: UUID
        let modelId: String?
        let reasoningLevel: String?
    }

    static let shared = ThreadManager()

    weak var delegate: ThreadManagerDelegate?

    let persistence = PersistenceService.shared
    let git = GitService.shared
    let tmux = TmuxService.shared

    // MARK: - Extracted service containers (Phase 1)

    let store = ThreadStore()
    let sessionTracker = SessionTracker()
    private let threadMutationGate = SerialAsyncOperationGate()
    let tabMigrationOperationGate = SerialAsyncOperationGate()

    // MARK: - Extracted service containers (Phase 2)

    lazy var rateLimitService: RateLimitService = {
        let svc = RateLimitService(store: store, persistence: persistence, tmux: tmux)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.resolveAgentType = { [weak self] thread, sessionName in
            self?.agentType(for: thread, sessionName: sessionName)
        }
        // Wire the resume-needed callback so clearing a rate limit can inject
        // per-session waiting markers and dedup state back into ThreadManager.
        svc.onRateLimitLiftResumeNeeded = { [weak self] sessions in
            guard let self else { return }
            self.rateLimitLiftPendingResumeSessions.formUnion(sessions)
            self.notifiedWaitingSessions.formUnion(sessions)
        }
        return svc
    }()

    lazy var pullRequestService: PullRequestService = {
        let svc = PullRequestService(store: store, persistence: persistence, git: git)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.resolveBaseBranch = { [weak self] thread in
            self?.resolveBaseBranch(for: thread) ?? ""
        }
        svc.cachedRemoteResolver = { [weak self] projectId, repoPath in
            await self?.cachedPullRequestRemote(for: projectId, repoPath: repoPath)
        }
        svc.formatFailureSummary = { [weak self] title, details, total in
            self?.statusSyncFailureSummary(title: title, details: details, totalCount: total) ?? "\(title)."
        }
        return svc
    }()

    lazy var jiraIntegrationService: JiraIntegrationService = {
        let svc = JiraIntegrationService(store: store, persistence: persistence)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        return svc
    }()

    lazy var sidebarOrderingService: SidebarOrderingService = {
        let svc = SidebarOrderingService(store: store, persistence: persistence)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        return svc
    }()

    lazy var gitStateService: GitStateService = {
        let svc = GitStateService(store: store, persistence: persistence, tmux: tmux, git: git)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.onBranchesChanged = { [weak self] changedIds in
            await self?.verifyDetectedJiraTickets(forThreadIds: changedIds)
        }
        svc.onBranchSymlinkNeeded = { [weak self] branchName, worktreePath, worktreesBasePath in
            self?.ensureBranchSymlink(
                branchName: branchName,
                worktreePath: worktreePath,
                worktreesBasePath: worktreesBasePath
            )
        }
        svc.cachedRemoteResolver = { [weak self] projectId in
            self?._cachedRemoteByProjectId[projectId]
        }
        return svc
    }()

    lazy var worktreeService: WorktreeService = {
        let svc = WorktreeService(store: store, persistence: persistence, tmux: tmux, git: git)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.resolveBaseBranchForThread = { [weak self] thread in
            self?.gitStateService.resolveBaseBranch(for: thread) ?? thread.baseBranch ?? ""
        }
        return svc
    }()

    // MARK: - Extracted service containers (Phase 4)

    lazy var sessionLifecycleService: SessionLifecycleService = {
        let svc = SessionLifecycleService(store: store, sessionTracker: sessionTracker, persistence: persistence, tmux: tmux)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.cacheThreadSessionState()
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.onSessionStateChanged = { [weak self] in
            self?.cacheThreadSessionState()
        }
        svc.recreateSession = { [weak self] sessionName, thread in
            await self?.recreateSessionIfNeeded(sessionName: sessionName, thread: thread) ?? false
        }
        svc.agentType = { [weak self] thread, sessionName in
            self?.agentType(for: thread, sessionName: sessionName)
        }
        // isSessionProtectedByRateLimit callback is intentionally nil — the service checks
        // thread.rateLimitedSessions[sessionName] directly and never calls this callback.
        svc.updateDockBadge = { [weak self] in
            self?.updateDockBadge()
        }
        svc.requestDockBounce = { [weak self] in
            self?.requestDockBounceForUnreadCompletionIfNeeded()
        }
        svc.bumpThreadToTop = { [weak self] threadId in
            self?.bumpThreadToTopOfSection(threadId)
        }
        svc.scheduleConversationIDRefresh = { [weak self] threadId, sessionName in
            self?.scheduleAgentConversationIDRefresh(threadId: threadId, sessionName: sessionName)
        }
        svc.triggerAutoRename = { [weak self] threadId, sessionName in
            await self?.triggerAutoRenameFromBellIfNeeded(threadId: threadId, sessionName: sessionName)
        }
        svc.refreshDirtyState = { [weak self] threadId in
            _ = await self?.refreshDirtyState(for: threadId)
        }
        svc.refreshDeliveredState = { [weak self] threadId in
            _ = await self?.refreshDeliveredState(for: threadId)
        }
        svc.refreshJiraTicketsForCompletedThreads = { [weak self] threadIds in
            await self?.verifyDetectedJiraTickets(forThreadIds: threadIds, reason: .agentCompletion)
        }
        svc.postBusySessionsChanged = { [weak self] thread in
            self?.postBusySessionsChangedNotification(for: thread)
        }
        svc.clearRateLimitAfterRecovery = { [weak self] threadId, sessionName, paneContent in
            await self?.clearRateLimitAfterRecovery(threadId: threadId, sessionName: sessionName, paneContent: paneContent) ?? []
        }
        svc.applyRateLimitMarker = { [weak self] info, agentType, runtimeSessions in
            guard let self else { return (false, []) }
            var ids = Set<UUID>()
            let changed = self.applyRateLimitMarker(info, for: agentType, runtimeActiveSessionsByAgent: runtimeSessions, changedThreadIds: &ids)
            return (changed, ids)
        }
        svc.clearPromptRateLimitMarkers = { [weak self] agentType in
            guard let self else { return (false, []) }
            var ids = Set<UUID>()
            let changed = self.clearPromptRateLimitMarkers(for: agentType, changedThreadIds: &ids)
            return (changed, ids)
        }
        svc.paneHasActiveNonIgnoredRateLimit = { [weak self] agentType, content, lastPrompt, sessionName in
            self?.paneHasActiveNonIgnoredRateLimit(
                for: agentType,
                paneContent: content,
                lastSubmittedPrompt: lastPrompt,
                sessionName: sessionName
            ) ?? false
        }
        svc.publishRateLimitSummary = { [weak self] in
            await self?.publishRateLimitSummaryIfNeeded()
        }
        svc.detectedAgentType = { [weak self] command in
            self?.detectedAgentType(from: command)
        }
        svc.detectedRunningAgentType = { [weak self] command, children in
            self?.detectedRunningAgentType(paneCommand: command, childProcesses: children)
        }
        svc.detectedAgentTypeInSession = { [weak self] sessionName in
            await self?.detectedAgentTypeInSession(sessionName)
        }
        return svc
    }()

    // MARK: - Extracted service containers (Phase 5)

    lazy var sessionRecreationService: SessionRecreationService = {
        let svc = SessionRecreationService(store: store, sessionTracker: sessionTracker, persistence: persistence, tmux: tmux)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.cacheThreadSessionState()
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.agentType = { [weak self] thread, sessionName in
            self?.agentType(for: thread, sessionName: sessionName)
        }
        svc.effectiveAgentType = { [weak self] projectId in
            self?.effectiveAgentType(for: projectId)
        }
        svc.detectedAgentTypeInSession = { [weak self] sessionName in
            await self?.detectedAgentTypeInSession(sessionName)
        }
        svc.sessionEnvironmentVariables = { [weak self] threadId, worktreePath, projectPath, worktreeName, projectName, agentType in
            self?.sessionEnvironmentVariables(
                threadId: threadId,
                worktreePath: worktreePath,
                projectPath: projectPath,
                worktreeName: worktreeName,
                projectName: projectName,
                agentType: agentType
            ) ?? []
        }
        svc.shellExportCommand = { [weak self] env in
            self?.shellExportCommand(for: env) ?? ""
        }
        svc.applySessionEnvironmentVariables = { [weak self] sessionName, env in
            await self?.applySessionEnvironmentVariables(sessionName: sessionName, environmentVariables: env)
        }
        svc.agentStartCommand = { [weak self] settings, projectId, agentType, envExports, workingDir, resumeID in
            self?.agentStartCommand(
                settings: settings,
                projectId: projectId,
                agentType: agentType,
                envExports: envExports,
                workingDirectory: workingDir,
                resumeSessionID: resumeID
            ) ?? ""
        }
        svc.terminalStartCommand = { [weak self] envExports, workingDir in
            self?.terminalStartCommand(envExports: envExports, workingDirectory: workingDir) ?? ""
        }
        svc.effectiveInjection = { [weak self] projectId in
            self?.effectiveInjection(for: projectId) ?? (terminalCommand: "", agentContext: "")
        }
        svc.injectAfterStart = { [weak self] sessionName, terminalCmd, agentCtx, agentType in
            self?.injectAfterStart(
                sessionName: sessionName,
                terminalCommand: terminalCmd,
                agentContext: agentCtx,
                agentType: agentType
            )
        }
        svc.refreshAgentConversationID = { [weak self] threadId, sessionName in
            await self?.refreshAgentConversationID(threadId: threadId, sessionName: sessionName)
        }
        return svc
    }()

    lazy var agentSetupService: AgentSetupService = {
        let svc = AgentSetupService(store: store, sessionTracker: sessionTracker, persistence: persistence, tmux: tmux, git: git)
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.hasActiveRateLimit = { [weak self] agent, now in
            self?.rateLimitService.hasActiveRateLimit(for: agent, now: now) ?? false
        }
        svc.effectiveAgentTypeForProject = { [weak self] projectId in
            self?.effectiveAgentType(for: projectId)
        }
        svc.triggerAutoRenameIfNeeded = { [weak self] threadId, sessionName, prompt in
            _ = await self?.autoRenameThreadAfterFirstPromptIfNeeded(
                threadId: threadId,
                sessionName: sessionName,
                prompt: prompt
            )
        }
        svc.triggerAutoRenameTabIfNeeded = { [weak self] threadId, sessionName, prompt in
            await self?.renameService.autoRenameTabIfNeeded(
                threadId: threadId,
                sessionName: sessionName,
                prompt: prompt
            )
        }
        return svc
    }()

    // MARK: - Extracted service containers (Phase 6)

    lazy var renameService: RenameService = {
        let svc = RenameService(
            store: store,
            persistence: persistence,
            tmux: tmux,
            git: git,
            threadMutationGate: threadMutationGate
        )
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.effectiveAgentType = { [weak self] projectId in
            self?.effectiveAgentType(for: projectId)
        }
        svc.detectedAgentTypeInSession = { [weak self] sessionName in
            await self?.detectedAgentTypeInSession(sessionName)
        }
        svc.verifyDetectedJiraTickets = { [weak self] threadIds in
            await self?.verifyDetectedJiraTickets(forThreadIds: threadIds)
        }
        svc.ensureBranchSymlink = { [weak self] branchName, worktreePath, basePath in
            self?.ensureBranchSymlink(
                branchName: branchName,
                worktreePath: worktreePath,
                worktreesBasePath: basePath
            )
        }
        svc.allocateUniqueTabDisplayNameCallback = { [weak self] requestedName, threadIndex, sessionName in
            self?.allocateUniqueTabDisplayName(
                requestedName: requestedName,
                threadIndex: threadIndex,
                excludingSessionName: sessionName
            ) ?? requestedName
        }
        svc.onTabAutoRenameStateChanged = { sessionName, isInProgress in
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .magentTabAutoRenameStateChanged,
                    object: nil,
                    userInfo: [
                        "sessionName": sessionName,
                        "isInProgress": isInProgress,
                    ]
                )
            }
        }
        return svc
    }()

    lazy var threadLifecycleService: ThreadLifecycleService = {
        let svc = ThreadLifecycleService(
            store: store,
            sessionTracker: sessionTracker,
            persistence: persistence,
            tmux: tmux,
            git: git,
            threadMutationGate: threadMutationGate
        )
        svc.onThreadsChanged = { [weak self] in
            guard let self else { return }
            self.delegate?.threadManager(self, didUpdateThreads: self.store.threads)
        }
        svc.onThreadCreated = { [weak self] thread in
            guard let self else { return }
            self.delegate?.threadManager(self, didCreateThread: thread)
        }
        svc.onThreadArchived = { [weak self] thread in
            guard let self else { return }
            self.delegate?.threadManager(self, didArchiveThread: thread)
        }
        svc.onThreadDeleted = { [weak self] thread in
            guard let self else { return }
            self.delegate?.threadManager(self, didDeleteThread: thread)
        }
        // Agent setup
        svc.resolveAgentType = { [weak self] projectId, requested, settings in
            self?.resolveAgentType(for: projectId, requestedAgentType: requested, settings: settings)
        }
        svc.agentStartCommand = { [weak self] settings, projectId, agentType, envExports, workingDir, resumeSessionID, requiresSuccessfulResume, modelId, reasoningLevel, codexFastMode in
            self?.agentStartCommand(
                settings: settings,
                projectId: projectId,
                agentType: agentType,
                envExports: envExports,
                workingDirectory: workingDir,
                resumeSessionID: resumeSessionID,
                requiresSuccessfulResume: requiresSuccessfulResume,
                modelId: modelId,
                reasoningLevel: reasoningLevel,
                codexFastMode: codexFastMode
            ) ?? ""
        }
        svc.terminalStartCommand = { [weak self] envExports, workingDir in
            self?.terminalStartCommand(envExports: envExports, workingDirectory: workingDir) ?? ""
        }
        svc.trustDirectoryIfNeeded = { [weak self] path, agentType in
            self?.trustDirectoryIfNeeded(path, agentType: agentType)
        }
        svc.effectiveAgentType = { [weak self] projectId in
            self?.effectiveAgentType(for: projectId)
        }
        svc.resolvedModelLabel = { [weak self] agentType, modelId in
            self?.resolvedModelLabel(for: agentType, modelId: modelId)
        }
        svc.sessionEnvironmentVariables = { [weak self] threadId, worktreePath, projectPath, worktreeName, projectName, agentType in
            self?.sessionEnvironmentVariables(
                threadId: threadId,
                worktreePath: worktreePath,
                projectPath: projectPath,
                worktreeName: worktreeName,
                projectName: projectName,
                agentType: agentType
            ) ?? []
        }
        svc.shellExportCommand = { [weak self] env in
            self?.shellExportCommand(for: env) ?? ""
        }
        svc.applySessionEnvironmentVariables = { [weak self] sessionName, env in
            await self?.applySessionEnvironmentVariables(sessionName: sessionName, environmentVariables: env)
        }
        svc.markSessionContextKnownGood = { [weak self] sessionName, threadId, expectedPath, projectPath, isAgent in
            self?.markSessionContextKnownGood(
                sessionName: sessionName,
                threadId: threadId,
                expectedPath: expectedPath,
                projectPath: projectPath,
                isAgentSession: isAgent
            )
        }
        svc.effectiveInjection = { [weak self] projectId in
            self?.effectiveInjection(for: projectId) ?? (terminalCommand: "", agentContext: "")
        }
        svc.injectAfterStart = { [weak self] sessionName, terminalCmd, agentCtx, initialPrompt, submit, agentType in
            self?.injectAfterStart(
                sessionName: sessionName,
                terminalCommand: terminalCmd,
                agentContext: agentCtx,
                initialPrompt: initialPrompt,
                shouldSubmitInitialPrompt: submit,
                agentType: agentType
            )
        }
        svc.scheduleAgentConversationIDRefresh = { [weak self] threadId, sessionName in
            self?.scheduleAgentConversationIDRefresh(threadId: threadId, sessionName: sessionName)
        }
        svc.registerPendingPromptCleanup = { [weak self] fileURL, sessionName in
            self?.registerPendingPromptCleanup(fileURL: fileURL, sessionName: sessionName)
        }
        // Rename / auto-rename
        svc.autoRenameThreadAfterFirstPromptIfNeeded = { [weak self] threadId, sessionName, prompt in
            await self?.renameService.autoRenameThreadAfterFirstPromptIfNeeded(
                threadId: threadId,
                sessionName: sessionName,
                prompt: prompt
            ) ?? false
        }
        svc.autoRenameTabIfNeeded = { [weak self] threadId, sessionName, prompt in
            await self?.renameService.autoRenameTabIfNeeded(
                threadId: threadId,
                sessionName: sessionName,
                prompt: prompt
            )
        }
        svc.cleanupRenameStateForThread = { [weak self] threadId in
            self?.renameService.cleanupForThread(id: threadId)
        }
        // Agent setup cleanup
        svc.cleanupAgentSetupForThread = { [weak self] threadId in
            self?.agentSetupService.cleanupPendingPromptRecoveries(for: threadId)
        }
        svc.clearTrackedInitialPromptInjectionForSessions = { [weak self] sessions in
            self?.clearTrackedInitialPromptInjection(forSessions: sessions)
        }
        // Sidebar ordering
        svc.placeThreadAfterSibling = { [weak self] threadId, afterId in
            self?.placeThreadAfterSibling(threadId: threadId, afterThreadId: afterId)
        }
        svc.bumpThreadToTopOfSection = { [weak self] threadId in
            self?.bumpThreadToTopOfSection(threadId)
        }
        // Local file sync
        svc.syncConfiguredLocalPathsIntoWorktree = { [weak self] project, worktreePath, entries, sourceOverride in
            try await self?.syncConfiguredLocalPathsIntoWorktree(
                project: project,
                worktreePath: worktreePath,
                syncEntries: entries,
                sourceRootOverride: sourceOverride
            ) ?? []
        }
        svc.effectiveLocalSyncEntries = { [weak self] thread, project in
            self?.effectiveLocalSyncEntries(for: thread, project: project) ?? []
        }
        svc.resolveBaseBranchSyncTargetForThread = { [weak self] thread, project in
            self?.resolveBaseBranchSyncTarget(for: thread, project: project) ?? (project.repoPath, "")
        }
        svc.resolveBaseBranchSyncTargetForBranch = { [weak self] baseBranch, threadId, projectId, project in
            self?.resolveBaseBranchSyncTarget(
                baseBranch: baseBranch,
                excludingThreadId: threadId,
                projectId: projectId,
                project: project
            ) ?? (project.repoPath, "")
        }
        svc.syncConfiguredLocalPathsFromWorktreeAsync = { [weak self] project, worktreePath, entries, promptConflicts, destOverride in
            try await self?.syncConfiguredLocalPathsFromWorktree(
                project: project,
                worktreePath: worktreePath,
                syncEntries: entries,
                promptForConflicts: promptConflicts,
                destinationRootOverride: destOverride
            )
        }
        // Git state
        svc.worktreeActiveNames = { [weak self] projectId in
            self?.worktreeActiveNames(for: projectId) ?? []
        }
        svc.referencedMagentSessionNames = { [weak self] in
            self?.referencedMagentSessionNames() ?? []
        }
        svc.pruneWorktreeCache = { [weak self] project in
            self?.pruneWorktreeCache(for: project)
        }
        svc.ensureBranchSymlink = { [weak self] branchName, worktreePath, basePath in
            self?.ensureBranchSymlink(
                branchName: branchName,
                worktreePath: worktreePath,
                worktreesBasePath: basePath
            )
        }
        // Jira
        svc.excludeJiraTicket = { [weak self] key, projectId in
            self?.excludeJiraTicket(key: key, projectId: projectId)
        }
        svc.verifyDetectedJiraTickets = { [weak self] threadIds in
            await self?.verifyDetectedJiraTickets(forThreadIds: threadIds)
        }
        // Session state
        svc.notifiedWaitingSessionsRemove = { [weak self] sessions in
            self?.notifiedWaitingSessions.subtract(sessions)
        }
        svc.rateLimitLiftPendingResumeSessionsRemove = { [weak self] sessions in
            self?.rateLimitLiftPendingResumeSessions.subtract(sessions)
        }
        return svc
    }()

    // MARK: - ThreadStore forwarding

    var threads: [MagentThread] {
        get { store.threads }
        set { store.threads = newValue }
    }
    var activeThreadId: UUID? {
        get { store.activeThreadId }
        set { store.activeThreadId = newValue }
    }
    var pendingThreadIds: Set<UUID> {
        get { store.pendingThreadIds }
        set { store.pendingThreadIds = newValue }
    }
    /// When true, the next `didCreateThread` delegate call will skip sidebar auto-selection.
    var skipNextAutoSelect: Bool {
        get { store.skipNextAutoSelect }
        set { store.skipNextAutoSelect = newValue }
    }

    // MARK: - SessionTracker forwarding

    var knownGoodSessionContexts: [String: KnownGoodSessionContext] {
        get { sessionTracker.knownGoodSessionContexts }
        set { sessionTracker.knownGoodSessionContexts = newValue }
    }
    var sessionLastVisitedAt: [String: Date] {
        get { sessionTracker.sessionLastVisitedAt }
        set { sessionTracker.sessionLastVisitedAt = newValue }
    }
    var sessionLastBusyAt: [String: Date] {
        get { sessionTracker.sessionLastBusyAt }
        set { sessionTracker.sessionLastBusyAt = newValue }
    }
    var evictedIdleSessions: Set<String> {
        get { sessionTracker.evictedIdleSessions }
        set { sessionTracker.evictedIdleSessions = newValue }
    }
    var sessionsBeingRecreated: Set<String> {
        get { sessionTracker.sessionsBeingRecreated }
        set { sessionTracker.sessionsBeingRecreated = newValue }
    }
    var rendererUnhealthySessions: Set<String> {
        get { sessionTracker.rendererUnhealthySessions }
        set { sessionTracker.rendererUnhealthySessions = newValue }
    }
    var replayCorruptedSessions: Set<String> {
        get { sessionTracker.replayCorruptedSessions }
        set { sessionTracker.replayCorruptedSessions = newValue }
    }
    var lastRuntimeDetectedAgentBySession: [String: (agent: AgentType, detectedAt: Date)] {
        get { sessionTracker.lastRuntimeDetectedAgentBySession }
        set { sessionTracker.lastRuntimeDetectedAgentBySession = newValue }
    }
    static let lastRuntimeDetectedAgentTTL: TimeInterval = SessionTracker.lastRuntimeDetectedAgentTTL

    // MARK: - SessionLifecycleService forwarding

    var recentBellBySession: [String: Date] {
        get { sessionLifecycleService.recentBellBySession }
        set { sessionLifecycleService.recentBellBySession = newValue }
    }
    var notifiedWaitingSessions: Set<String> {
        get { sessionLifecycleService.notifiedWaitingSessions }
        set { sessionLifecycleService.notifiedWaitingSessions = newValue }
    }
    var rateLimitLiftPendingResumeSessions: Set<String> {
        get { sessionLifecycleService.rateLimitLiftPendingResumeSessions }
        set { sessionLifecycleService.rateLimitLiftPendingResumeSessions = newValue }
    }
    var staleMagentSessionsFirstSeenAt: [String: Date] {
        get { sessionLifecycleService.staleMagentSessionsFirstSeenAt }
        set { sessionLifecycleService.staleMagentSessionsFirstSeenAt = newValue }
    }
    var lastStaleSessionCleanupAt: Date {
        get { sessionLifecycleService.lastStaleSessionCleanupAt }
        set { sessionLifecycleService.lastStaleSessionCleanupAt = newValue }
    }

    // MARK: - RateLimitService forwarding

    var globalAgentRateLimits: [AgentType: AgentRateLimitInfo] {
        get { rateLimitService.globalAgentRateLimits }
        set { rateLimitService.globalAgentRateLimits = newValue }
    }
    var rateLimitFingerprintCache: [String: RateLimitCacheEntry] {
        get { rateLimitService.rateLimitFingerprintCache }
        set { rateLimitService.rateLimitFingerprintCache = newValue }
    }
    var ignoredRateLimitFingerprintsByAgent: [AgentType: Set<String>] {
        get { rateLimitService.ignoredRateLimitFingerprintsByAgent }
        set { rateLimitService.ignoredRateLimitFingerprintsByAgent = newValue }
    }
    var rateLimitCacheLoaded: Bool {
        get { rateLimitService.rateLimitCacheLoaded }
        set { rateLimitService.rateLimitCacheLoaded = newValue }
    }
    var rateLimitCacheDirty: Bool {
        get { rateLimitService.rateLimitCacheDirty }
        set { rateLimitService.rateLimitCacheDirty = newValue }
    }
    var ignoredRateLimitCacheLoaded: Bool {
        get { rateLimitService.ignoredRateLimitCacheLoaded }
        set { rateLimitService.ignoredRateLimitCacheLoaded = newValue }
    }
    var ignoredRateLimitCacheDirty: Bool {
        get { rateLimitService.ignoredRateLimitCacheDirty }
        set { rateLimitService.ignoredRateLimitCacheDirty = newValue }
    }
    var lastPublishedRateLimitSummary: String? {
        get { rateLimitService.lastPublishedRateLimitSummary }
        set { rateLimitService.lastPublishedRateLimitSummary = newValue }
    }
    var lastRateLimitScanBySession: [String: Date] {
        get { rateLimitService.lastRateLimitScanBySession }
        set { rateLimitService.lastRateLimitScanBySession = newValue }
    }

    // MARK: - PullRequestService forwarding

    var isPRSyncRunning: Bool {
        get { pullRequestService.isPRSyncRunning }
        set { pullRequestService.isPRSyncRunning = newValue }
    }
    var prCache: [String: PullRequestCacheEntry] {
        get { pullRequestService.prCache }
        set { pullRequestService.prCache = newValue }
    }
    var prCacheLoaded: Bool {
        get { pullRequestService.prCacheLoaded }
        set { pullRequestService.prCacheLoaded = newValue }
    }

    // MARK: - JiraIntegrationService forwarding

    var jiraTicketCache: [String: JiraTicketCacheEntry] {
        get { jiraIntegrationService.jiraTicketCache }
        set { jiraIntegrationService.jiraTicketCache = newValue }
    }
    var jiraTicketCacheLoaded: Bool {
        get { jiraIntegrationService.jiraTicketCacheLoaded }
        set { jiraIntegrationService.jiraTicketCacheLoaded = newValue }
    }
    var isJiraVerificationRunning: Bool {
        get { jiraIntegrationService.isJiraVerificationRunning }
        set { jiraIntegrationService.isJiraVerificationRunning = newValue }
    }
    var _jiraProjectStatusesCache: [String: [JiraProjectStatus]] {
        get { jiraIntegrationService._jiraProjectStatusesCache }
        set { jiraIntegrationService._jiraProjectStatusesCache = newValue }
    }
    var _jiraProjectStatusesCacheLoaded: Bool {
        get { jiraIntegrationService._jiraProjectStatusesCacheLoaded }
        set { jiraIntegrationService._jiraProjectStatusesCacheLoaded = newValue }
    }

    // MARK: - GitStateService forwarding

    var baseBranchResets: [UUID: BaseBranchReset] {
        get { gitStateService.baseBranchResets }
        set { gitStateService.baseBranchResets = newValue }
    }

    // MARK: - AgentSetupService forwarding

    var initialPromptInjectionFailuresBySession: [String: InitialPromptInjectionFailureInfo] {
        get { agentSetupService.initialPromptInjectionFailuresBySession }
        set { agentSetupService.initialPromptInjectionFailuresBySession = newValue }
    }
    var pendingPromptInjectionSessions: [String: InitialPromptInjectionFailureInfo] {
        get { agentSetupService.pendingPromptInjectionSessions }
        set { agentSetupService.pendingPromptInjectionSessions = newValue }
    }
    var pendingPromptInjectionTasks: [String: Task<Void, Never>] {
        get { agentSetupService.pendingPromptInjectionTasks }
        set { agentSetupService.pendingPromptInjectionTasks = newValue }
    }
    var initialPromptInjectionCompletionsBySession: [String: Date] {
        get { agentSetupService.initialPromptInjectionCompletionsBySession }
        set { agentSetupService.initialPromptInjectionCompletionsBySession = newValue }
    }
    var initialPromptAutoRelaunchAttempts: Set<String> {
        get { agentSetupService.initialPromptAutoRelaunchAttempts }
        set { agentSetupService.initialPromptAutoRelaunchAttempts = newValue }
    }
    var pendingPromptRecoveriesByThread: [UUID: [PendingPromptRecoveryInfo]] {
        get { agentSetupService.pendingPromptRecoveriesByThread }
        set { agentSetupService.pendingPromptRecoveriesByThread = newValue }
    }

    // MARK: - RenameService forwarding

    var autoRenameInProgress: Set<UUID> {
        get { renameService.autoRenameInProgress }
        set { renameService.autoRenameInProgress = newValue }
    }
    var autoTabRenameInProgress: Set<String> {
        renameService.autoTabRenameInProgress
    }
    var promptRenameResultCache: [UUID: [String: CachedRenameResult]] {
        get { renameService.promptRenameResultCache }
        set { renameService.promptRenameResultCache = newValue }
    }

    // MARK: - Remaining inline state

    // baseBranchResets is forwarded to gitStateService — see forwarding computed property above.
    var sessionMonitorTimer: Timer?
    var isSessionMonitorTickRunning = false
    var isForegroundRefreshRunning = false
    var lastTmuxZombieHealthCheckAt: Date = .distantPast
    var lastTmuxZombieSummary: TmuxService.ZombieParentSummary?
    var didShowTmuxZombieWarning = false
    var isRestartingTmuxForRecovery = false
    var _slowTickCounter: Int = 0
    var dirtyCheckTickCounter: Int = 0
    var _jiraSyncTickCounter: Int = 0
    var _prSyncTickCounter: Int = 0
    /// Timestamp of the last completed PR + Jira background sync pass.
    var lastStatusSyncAt: Date?
    /// Whether the last sync pass encountered errors (network, auth, etc.).
    var lastStatusSyncFailed = false
    /// Human-readable summary of the most recent sync failure, used by the status bar.
    var lastStatusSyncFailureSummary: String?
    var _cachedRemoteByProjectId: [UUID: GitRemote] = [:]
    private var lastCachedThreadSessionState: ThreadSessionStateCache?
    private var hasPrimedThreadsForPendingRestore = false
    /// Non-persisted per-thread stack of recently closed tabs used by Cmd+Shift+T.
    var closedTabHistoryByThreadId: [UUID: ClosedTabHistoryBuffer] = [:]

    // MARK: - Lifecycle

    func loadThreads() {
        threads = persistence.loadThreads().filter { !$0.isArchived }
    }

    private func restoreCachedSidebarStatus() {
        populateJiraInfoFromCache()
        populatePRInfoFromCache()

        guard let cache = persistence.loadThreadSessionStateCache() else { return }
        evictedIdleSessions = cache.restore(into: &threads)
        lastCachedThreadSessionState = cache
    }

    func cacheThreadSessionState() {
        let cache = ThreadSessionStateCache(
            threads: threads,
            evictedSessions: evictedIdleSessions
        )
        guard cache != lastCachedThreadSessionState else { return }
        lastCachedThreadSessionState = cache
        persistence.saveThreadSessionStateCache(cache)
    }

    func primePersistedThreadsForLaunch() {
        loadThreads()
        restoreCachedSidebarStatus()
        hasPrimedThreadsForPendingRestore = true
        delegate?.threadManager(self, didUpdateThreads: threads)
        NotificationCenter.default.post(name: .magentThreadsDidChange, object: nil)
    }

    func restoreThreads() async {
        if hasPrimedThreadsForPendingRestore {
            hasPrimedThreadsForPendingRestore = false
        } else {
            loadThreads()
            restoreCachedSidebarStatus()
        }
        installClaudeHooksSettings()
        ensureCodexBellNotification()
        installCodexIPCInstructions()

        // Migrate old threads that have no agentTmuxSessions recorded.
        // Heuristic: the first session was always created as the agent tab.
        let settings = persistence.loadSettings()
        await threadLifecycleService.recoverInterruptedTabMoves(projects: settings.projects)
        var didMigrate = false
        let migrationThreadIds = threads.map(\.id)
        for threadId in migrationThreadIds {
            guard let initialIndex = store.threadIndex(byId: threadId) else { continue }
            let codexReconciledChatTabs = CodexChatTranscriptReconciler.reconciledChatTabsForRestore(
                threads[initialIndex].persistedChatTabs
            )
            if codexReconciledChatTabs.didMutate {
                threads[initialIndex].persistedChatTabs = codexReconciledChatTabs.chatTabs
                didMigrate = true
            }
            let claudeReconciledChatTabs = ClaudeChatTranscriptReconciler.reconciledChatTabsForRestore(
                threads[initialIndex].persistedChatTabs
            )
            if claudeReconciledChatTabs.didMutate {
                threads[initialIndex].persistedChatTabs = claudeReconciledChatTabs.chatTabs
                didMigrate = true
            }
            let normalizedChatTabs = ChatBusyStateRecovery.normalizedChatTabsForAppRelaunch(
                threads[initialIndex].persistedChatTabs
            )
            if normalizedChatTabs.didMutate {
                threads[initialIndex].persistedChatTabs = normalizedChatTabs.chatTabs
                didMigrate = true
            }
            if threads[initialIndex].agentTmuxSessions.isEmpty && !threads[initialIndex].tmuxSessionNames.isEmpty {
                threads[initialIndex].agentTmuxSessions = [threads[initialIndex].tmuxSessionNames[0]]
                didMigrate = true
            }
            // Migrate: existing threads with agent sessions must have had the agent run.
            if !threads[initialIndex].agentHasRun && !threads[initialIndex].agentTmuxSessions.isEmpty {
                threads[initialIndex].agentHasRun = true
                didMigrate = true
            }
            // Keep persisted conversation IDs only for known agent sessions.
            let validAgentSessions = Set(threads[initialIndex].agentTmuxSessions)
            let filteredConversationIDs = threads[initialIndex].sessionConversationIDs.filter { validAgentSessions.contains($0.key) }
            if filteredConversationIDs.count != threads[initialIndex].sessionConversationIDs.count {
                threads[initialIndex].sessionConversationIDs = filteredConversationIDs
                didMigrate = true
            }
            let validSessions = Set(threads[initialIndex].tmuxSessionNames)
            let filteredSessionCreatedAts = threads[initialIndex].sessionCreatedAts.filter { validSessions.contains($0.key) }
            if filteredSessionCreatedAts.count != threads[initialIndex].sessionCreatedAts.count {
                threads[initialIndex].sessionCreatedAts = filteredSessionCreatedAts
                didMigrate = true
            }
            let filteredFreshSessions = Set(threads[initialIndex].freshAgentSessions.filter { validAgentSessions.contains($0) })
            if filteredFreshSessions.count != threads[initialIndex].freshAgentSessions.count {
                threads[initialIndex].freshAgentSessions = filteredFreshSessions
                didMigrate = true
            }
            if await migrateSessionAgentTypes(threadId: threadId) {
                didMigrate = true
            }
            guard let i = store.threadIndex(byId: threadId) else { continue }
            if pruneSessionAgentTypesToKnownSessions(threadIndex: i) {
                didMigrate = true
            }
            if pruneSubmittedPromptHistoryToKnownSessions(threadIndex: i) {
                didMigrate = true
            }
            // Protect pre-existing custom tab names from auto-model-detection rewrites.
            // manuallyRenamedTabs decodes as [] from older JSON, so this runs once per
            // session on the first launch after the feature ships and is then a no-op
            // (the set is persisted and already contains the session on subsequent launches).
            for session in threads[i].tmuxSessionNames {
                guard !threads[i].manuallyRenamedTabs.contains(session) else { continue }
                let agentType = threads[i].sessionAgentTypes[session]
                let name = threads[i].customTabNames[session] ?? ""
                if !name.isEmpty && !TmuxSessionNaming.looksLikeDefaultTabName(name, for: agentType) {
                    threads[i].manuallyRenamedTabs.insert(session)
                    didMigrate = true
                }
            }
        }

        // Do NOT prune dead tmux session names — the attach-or-create pattern
        // in ThreadDetailViewController will recreate them when the user opens the thread.

        if didMigrate {
            try? persistence.saveActiveThreads(threads)
        }

        // Migrate session names from old magent- prefix to new ma- format
        await migrateSessionNamesToNewFormat()

        // Sync threads with worktrees on disk for each valid project
        for project in settings.projects where project.isValid {
            await syncThreadsWithWorktrees(for: project)
        }

        // Ensure every project has a main thread
        await ensureMainThreads()

        // Remove orphaned Magent tmux sessions that no longer map to an active thread/tab.
        await cleanupStaleMagentSessions()

        // Set up bell detection pipes on all live agent sessions.
        await ensureBellPipes()

        // Consume bell events that accumulated while the app was not running.
        // We map them to unread completion state at startup (instead of dropping
        // them), and intentionally do not touch recentBellBySession here so busy
        // process re-detection is not suppressed on relaunch.
        let startupCompletionEvents = await tmux.consumeAgentCompletionEvents()
        applyStartupCompletionEvents(startupCompletionEvents)

        // Seed visit timestamps so no sessions are evicted immediately after launch.
        let launchNow = Date()
        for thread in threads where !thread.isArchived {
            for session in thread.tmuxSessionNames {
                sessionLastVisitedAt[session] = launchNow
            }
        }

        // Sync busy state from actual tmux processes so spinners show immediately
        // after restart (busySessions is transient and starts empty on launch).
        await syncBusySessionsFromProcessState()

        // Populate dirty, delivered, and branch states at launch so indicators show immediately.
        await refreshDirtyStates()
        await refreshDeliveredStates()
        await refreshBranchStates()
        await verifyDetectedJiraTickets(reason: .appLaunch)
        populatePRInfoFromCache()
        let prSyncResult = await runPRSyncTick()
        lastStatusSyncAt = Date()
        lastStatusSyncFailed = prSyncResult.hadErrors
        lastStatusSyncFailureSummary = prSyncResult.failureSummary

        await MainActor.run {
            updateDockBadge()
            delegate?.threadManager(self, didUpdateThreads: threads)
            NotificationCenter.default.post(name: .magentStatusSyncCompleted, object: nil)
        }
    }

    /// Applies completion events collected during app downtime.
    /// This preserves unread completion indicators after relaunch without
    /// affecting transient busy/waiting state derived from live tmux processes.
    private func applyStartupCompletionEvents(_ events: [AgentCompletionEvent]) {
        guard !events.isEmpty else { return }

        let orderedUniqueEvents = events.reduce(into: [AgentCompletionEvent]()) { result, event in
            if let index = result.firstIndex(where: { $0.sessionName == event.sessionName }) {
                if event.completedAt > result[index].completedAt {
                    result[index] = event
                }
            } else {
                result.append(event)
            }
        }

        var changed = false
        for event in orderedUniqueEvents {
            let session = event.sessionName
            guard let index = threads.firstIndex(where: { !$0.isArchived && $0.agentTmuxSessions.contains(session) }) else {
                continue
            }

            threads[index].lastAgentCompletionAt = event.completedAt
            _ = threads[index].completePendingPromptTimings(for: session, at: event.completedAt)
            bumpThreadToTopOfSection(threads[index].id)

            let isActiveThread = threads[index].id == activeThreadId
            let isActiveTab = isActiveThread && threads[index].lastSelectedTabIdentifier == session
            if !isActiveTab {
                threads[index].unreadCompletionSessions.insert(session)
            }
            changed = true
        }

        if changed {
            try? persistence.saveActiveThreads(threads)
        }
    }
}

extension ThreadManager {
    func statusSyncFailureSummary(title: String, details: [String], totalCount: Int? = nil) -> String {
        let cleanedDetails = details
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let resolvedTotal = max(totalCount ?? cleanedDetails.count, cleanedDetails.count)

        guard !cleanedDetails.isEmpty else {
            return resolvedTotal > 0 ? "\(title) (\(resolvedTotal) error\(resolvedTotal == 1 ? "" : "s"))." : "\(title)."
        }

        var lines = ["\(title):"]
        for detail in cleanedDetails.prefix(3) {
            lines.append("- \(detail)")
        }

        let remaining = resolvedTotal - min(cleanedDetails.count, 3)
        if remaining > 0 {
            lines.append("- \(remaining) more error\(remaining == 1 ? "" : "s")")
        }

        return lines.joined(separator: "\n")
    }

    func mergeStatusSyncFailureSummaries(_ summaries: [String]) -> String? {
        let cleaned = summaries
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }
        return cleaned.joined(separator: "\n\n")
    }
}
