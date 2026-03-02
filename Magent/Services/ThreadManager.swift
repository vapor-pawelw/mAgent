import AppKit
import Foundation
import UserNotifications

@MainActor
protocol ThreadManagerDelegate: AnyObject {
    func threadManager(_ manager: ThreadManager, didCreateThread thread: MagentThread)
    func threadManager(_ manager: ThreadManager, didArchiveThread thread: MagentThread)
    func threadManager(_ manager: ThreadManager, didDeleteThread thread: MagentThread)
    func threadManager(_ manager: ThreadManager, didUpdateThreads threads: [MagentThread])
}

final class ThreadManager {

    static let shared = ThreadManager()

    weak var delegate: ThreadManagerDelegate?

    let persistence = PersistenceService.shared
    let git = GitService.shared
    let tmux = TmuxService.shared

    var threads: [MagentThread] = []
    var activeThreadId: UUID?
    var recentBellBySession: [String: Date] = [:]
    var autoRenameInProgress: Set<UUID> = []
    var pendingCwdEnforcements: [String: PendingCwdEnforcement] = [:]
    /// Dedup tracker — prevents repeated "waiting for input" notifications for the same session.
    var notifiedWaitingSessions: Set<String> = []
    /// Global per-agent rate-limit cache (Claude/Codex), shared across all tabs/threads.
    var globalAgentRateLimits: [AgentType: AgentRateLimitInfo] = [:]
    var lastPublishedRateLimitSummary: String?
    var sessionsBeingRecreated: Set<String> = []
    var sessionMonitorTimer: Timer?
    var lastTmuxZombieHealthCheckAt: Date = .distantPast
    var didShowTmuxZombieWarning = false
    var isRestartingTmuxForRecovery = false
    static let idleShellCommands: Set<String> = {
        let shellPath = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        let shellName = URL(fileURLWithPath: shellPath).lastPathComponent
        guard !shellName.isEmpty else { return ["zsh", "-zsh"] }
        return [shellName, "-\(shellName)"]
    }()
    var dirtyCheckTickCounter: Int = 0
    var _jiraSyncTickCounter: Int = 0
    var _mismatchBannerShownProjectIds: Set<UUID> = []

    // MARK: - Lifecycle

    func loadThreads() {
        threads = persistence.loadThreads().filter { !$0.isArchived }
    }

    func restoreThreads() async {
        loadThreads()
        installClaudeHooksSettings()
        ensureCodexBellNotification()
        let preSettings = persistence.loadSettings()
        if preSettings.ipcPromptInjectionEnabled {
            installCodexIPCInstructions()
        }

        // Migrate old threads that have no agentTmuxSessions recorded.
        // Heuristic: the first session was always created as the agent tab.
        let settings = persistence.loadSettings()
        var didMigrate = false
        for i in threads.indices {
            if threads[i].agentTmuxSessions.isEmpty && !threads[i].tmuxSessionNames.isEmpty {
                threads[i].agentTmuxSessions = [threads[i].tmuxSessionNames[0]]
                didMigrate = true
            }
            if threads[i].selectedAgentType == nil && !threads[i].agentTmuxSessions.isEmpty {
                threads[i].selectedAgentType = resolveAgentType(
                    for: threads[i].projectId,
                    requestedAgentType: nil,
                    settings: settings
                )
                didMigrate = true
            }
            // Migrate: existing threads with agent sessions must have had the agent run.
            if !threads[i].agentHasRun && !threads[i].agentTmuxSessions.isEmpty {
                threads[i].agentHasRun = true
                didMigrate = true
            }
            // Migrate: record per-session agent type for existing agent tabs.
            if !threads[i].agentTmuxSessions.isEmpty {
                let fallbackAgent = threads[i].selectedAgentType
                    ?? resolveAgentType(
                        for: threads[i].projectId,
                        requestedAgentType: nil,
                        settings: settings
                    )
                if let fallbackAgent {
                    for sessionName in threads[i].agentTmuxSessions
                    where threads[i].sessionAgentTypes[sessionName] == nil {
                        threads[i].sessionAgentTypes[sessionName] = fallbackAgent
                        didMigrate = true
                    }
                }
            }
        }

        // Do NOT prune dead tmux session names — the attach-or-create pattern
        // in ThreadDetailViewController will recreate them when the user opens the thread.

        if didMigrate {
            try? persistence.saveThreads(threads)
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
        let startupCompletionSessions = await tmux.consumeAgentCompletionSessions()
        applyStartupCompletionSessions(startupCompletionSessions)

        // Sync busy state from actual tmux processes so spinners show immediately
        // after restart (busySessions is transient and starts empty on launch).
        await syncBusySessionsFromProcessState()

        // Populate dirty, delivered, and branch states at launch so indicators show immediately.
        await refreshDirtyStates()
        await refreshDeliveredStates()
        await refreshBranchStates()

        await MainActor.run {
            updateDockBadge()
            delegate?.threadManager(self, didUpdateThreads: threads)
        }
    }

    /// Applies completion events collected during app downtime.
    /// This preserves unread completion indicators after relaunch without
    /// affecting transient busy/waiting state derived from live tmux processes.
    private func applyStartupCompletionSessions(_ sessions: [String]) {
        guard !sessions.isEmpty else { return }

        let now = Date()
        let orderedUniqueSessions = sessions.reduce(into: [String]()) { result, session in
            if !result.contains(session) {
                result.append(session)
            }
        }

        var changed = false
        for session in orderedUniqueSessions {
            guard let index = threads.firstIndex(where: { !$0.isArchived && $0.agentTmuxSessions.contains(session) }) else {
                continue
            }

            threads[index].lastAgentCompletionAt = now
            bumpThreadToTopOfSection(threads[index].id)

            let isActiveThread = threads[index].id == activeThreadId
            let isActiveTab = isActiveThread && threads[index].lastSelectedTmuxSessionName == session
            if !isActiveTab {
                threads[index].unreadCompletionSessions.insert(session)
            }
            changed = true
        }

        if changed {
            try? persistence.saveThreads(threads)
        }
    }

    // MARK: - Session Name Migration

    /// One-time migration: renames tmux sessions from the old `magent-` format to the new `ma-` format.
    private func migrateSessionNamesToNewFormat() async {
        let needsMigration = threads.contains { thread in
            thread.tmuxSessionNames.contains { $0.hasPrefix("magent-") }
        }
        guard needsMigration else { return }

        let settings = persistence.loadSettings()
        var changed = false

        for i in threads.indices {
            let thread = threads[i]
            guard thread.tmuxSessionNames.contains(where: { $0.hasPrefix("magent-") }) else { continue }
            guard let project = settings.projects.first(where: { $0.id == thread.projectId }) else { continue }

            let slug = TmuxSessionNaming.repoSlug(from: project.name)
            var renameMap: [String: String] = [:]
            var usedNames = Set<String>()

            for (tabIndex, sessionName) in thread.tmuxSessionNames.enumerated() {
                guard sessionName.hasPrefix("magent-") else {
                    usedNames.insert(sessionName)
                    continue
                }

                let customName = thread.customTabNames[sessionName]
                let displayName = (customName?.isEmpty == false)
                    ? customName!
                    : MagentThread.defaultDisplayName(at: tabIndex)
                let tabSlug = TmuxSessionNaming.sanitizeForTmux(displayName)

                let threadNamePart = thread.isMain ? nil : thread.name
                let baseName = TmuxSessionNaming.buildSessionName(repoSlug: slug, threadName: threadNamePart, tabSlug: tabSlug)

                var candidate = baseName
                if usedNames.contains(candidate) {
                    var suffix = 2
                    while usedNames.contains("\(baseName)-\(suffix)") {
                        suffix += 1
                    }
                    candidate = "\(baseName)-\(suffix)"
                }
                usedNames.insert(candidate)

                if candidate != sessionName {
                    renameMap[sessionName] = candidate
                }
            }

            guard !renameMap.isEmpty else { continue }

            // Rename live tmux sessions
            let oldNames = thread.tmuxSessionNames
            let newNames = oldNames.map { renameMap[$0] ?? $0 }
            try? await renameTmuxSessions(from: oldNames, to: newNames)

            // Update all references
            threads[i].tmuxSessionNames = newNames
            threads[i].agentTmuxSessions = threads[i].agentTmuxSessions.map { renameMap[$0] ?? $0 }
            threads[i].pinnedTmuxSessions = threads[i].pinnedTmuxSessions.map { renameMap[$0] ?? $0 }
            threads[i].unreadCompletionSessions = Set(
                threads[i].unreadCompletionSessions.map { renameMap[$0] ?? $0 }
            )
            threads[i].sessionAgentTypes = Dictionary(
                uniqueKeysWithValues: threads[i].sessionAgentTypes.map { key, value in
                    (renameMap[key] ?? key, value)
                }
            )
            var newCustomTabNames: [String: String] = [:]
            for (key, value) in threads[i].customTabNames {
                newCustomTabNames[renameMap[key] ?? key] = value
            }
            threads[i].customTabNames = newCustomTabNames
            if let selected = threads[i].lastSelectedTmuxSessionName {
                threads[i].lastSelectedTmuxSessionName = renameMap[selected] ?? selected
            }
            changed = true
        }

        if changed {
            try? persistence.saveThreads(threads)
        }
    }

    /// Ensures every live agent tmux session has a pipe-pane bell watcher set up.
    /// Called at startup and periodically from the session monitor.
    func ensureBellPipes() async {
        let pipedSessions = await tmux.sessionsWithActivePipe()
        for thread in threads where !thread.isArchived {
            for sessionName in thread.agentTmuxSessions {
                guard !pipedSessions.contains(sessionName) else { continue }
                // Only set up if the session is actually alive
                guard await tmux.hasSession(name: sessionName) else { continue }
                await tmux.setupBellPipe(for: sessionName)
            }
        }
    }
}
