import AppKit
import Foundation
import UserNotifications

extension ThreadManager {

    // MARK: - Agent Completions

    func checkForAgentCompletions() async {
        let sessions = await tmux.consumeAgentCompletionSessions()
        guard !sessions.isEmpty else { return }

        let now = Date()
        let settings = persistence.loadSettings()
        let playSound = settings.playSoundForAgentCompletion
        let orderedUniqueSessions = sessions.reduce(into: [String]()) { result, session in
            if !result.contains(session) {
                result.append(session)
            }
        }

        var changed = false
        var changedThreadIds = Set<UUID>()

        for session in orderedUniqueSessions {
            if let previous = recentBellBySession[session], now.timeIntervalSince(previous) < 1.0 {
                continue
            }
            recentBellBySession[session] = now

            guard let index = threads.firstIndex(where: { !$0.isArchived && $0.agentTmuxSessions.contains(session) }) else {
                continue
            }

            threads[index].lastAgentCompletionAt = now
            if settings.autoReorderThreadsOnAgentCompletion {
                bumpThreadToTopOfSection(threads[index].id)
            }
            threads[index].busySessions.remove(session)
            threads[index].waitingForInputSessions.remove(session)
            notifiedWaitingSessions.remove(session)

            let isActiveThread = threads[index].id == activeThreadId
            let isActiveTab = isActiveThread && threads[index].lastSelectedTmuxSessionName == session
            if !isActiveTab {
                threads[index].unreadCompletionSessions.insert(session)
            }
            changed = true
            changedThreadIds.insert(threads[index].id)

            let projectName = settings.projects.first(where: { $0.id == threads[index].projectId })?.name ?? "Project"
            sendAgentCompletionNotification(for: threads[index], projectName: projectName, playSound: playSound, sessionName: session)
        }

        guard changed else { return }
        try? persistence.saveThreads(threads)

        // Agent completed work — refresh dirty and delivered states for affected threads
        await refreshDirtyStates()
        for threadId in changedThreadIds {
            await refreshDeliveredState(for: threadId)
        }

        await MainActor.run {
            updateDockBadge()
            delegate?.threadManager(self, didUpdateThreads: threads)
            for threadId in changedThreadIds {
                if let thread = threads.first(where: { $0.id == threadId }) {
                    postBusySessionsChangedNotification(for: thread)
                }
            }
            for session in orderedUniqueSessions {
                if let index = threads.firstIndex(where: { !$0.isArchived && $0.agentTmuxSessions.contains(session) }) {
                    NotificationCenter.default.post(
                        name: .magentAgentCompletionDetected,
                        object: self,
                        userInfo: [
                            "threadId": threads[index].id,
                            "unreadSessions": threads[index].unreadCompletionSessions
                        ]
                    )
                }
            }
        }
    }

    private func sendAgentCompletionNotification(for thread: MagentThread, projectName: String, playSound: Bool, sessionName: String) {
        let settings = persistence.loadSettings()

        if settings.showSystemBanners {
            let content = UNMutableNotificationContent()
            content.title = "Agent Finished"
            content.body = "\(projectName) · \(thread.name)"
            if playSound {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(settings.agentCompletionSoundName))
            }
            content.userInfo = ["threadId": thread.id.uuidString, "sessionName": sessionName]

            let request = UNNotificationRequest(
                identifier: "magent-agent-finished-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

        // Play sound directly via NSSound as a fallback — UNNotification sound
        // can be throttled by macOS when many notifications are delivered.
        if playSound {
            let soundName = settings.agentCompletionSoundName
            DispatchQueue.main.async {
                if let sound = NSSound(named: NSSound.Name(soundName)) {
                    sound.play()
                } else {
                    NSSound.beep()
                }
            }
        }
    }

    // MARK: - Busy Session Sync

    /// Syncs `busySessions` with actual tmux pane state by checking `pane_current_command`.
    /// If the foreground process is a non-shell command, the session is busy.
    /// If it's the login shell for this app session, the agent has exited and the session is idle.
    /// This intentionally avoids treating every shell binary as idle because custom agent wrappers
    /// can run under `bash`/`sh` even while agent work is still in progress.
    func syncBusySessionsFromProcessState() async {
        // Collect all agent sessions across non-archived threads
        var allAgentSessions = Set<String>()
        for thread in threads where !thread.isArchived {
            allAgentSessions.formUnion(thread.agentTmuxSessions)
        }
        guard !allAgentSessions.isEmpty else { return }

        let paneStates = await tmux.activePaneStates(forSessions: allAgentSessions)
        guard !paneStates.isEmpty else { return }

        // Collect pane PIDs for shell sessions where the title doesn't indicate busy.
        // These need a child-process check to detect agents running inside the shell wrapper.
        var shellPidsToCheck = Set<pid_t>()
        for thread in threads where !thread.isArchived {
            for session in thread.agentTmuxSessions {
                guard let paneState = paneStates[session] else { continue }
                let isShell = Self.idleShellCommands.contains(paneState.command)
                let titleIndicatesBusy = paneTitleIndicatesBusy(paneState.title)
                if isShell && !titleIndicatesBusy && paneState.pid > 0 {
                    shellPidsToCheck.insert(paneState.pid)
                }
            }
        }
        let childrenByPid = await tmux.childPids(forParents: shellPidsToCheck)

        var changed = false
        var busyChangedThreadIds = Set<UUID>()
        var rateLimitChangedThreadIds = Set<UUID>()
        for i in threads.indices {
            guard !threads[i].isArchived else { continue }
            for session in threads[i].agentTmuxSessions {
                guard let paneState = paneStates[session] else { continue }
                let command = paneState.command
                let isShell = Self.idleShellCommands.contains(command)
                let titleIndicatesBusy = paneTitleIndicatesBusy(paneState.title)
                if isShell {
                    if titleIndicatesBusy && !threads[i].waitingForInputSessions.contains(session) {
                        // Both ✳ and braille spinner characters can persist in the pane
                        // title after the agent finishes. Always verify via pane content
                        // that the agent isn't just sitting at an empty prompt.
                        if let content = await tmux.capturePane(sessionName: session),
                           isAgentIdleAtPrompt(content) {
                            // Agent is idle — clear any stale busy state
                            if threads[i].busySessions.contains(session) {
                                threads[i].busySessions.remove(session)
                                changed = true
                                busyChangedThreadIds.insert(threads[i].id)
                            }
                            continue
                        }
                        if !threads[i].busySessions.contains(session) {
                            threads[i].busySessions.insert(session)
                            changed = true
                            busyChangedThreadIds.insert(threads[i].id)
                        }
                        let recoveredIds = clearRateLimitAfterRecovery(threadIndex: i, sessionName: session)
                        if !recoveredIds.isEmpty {
                            rateLimitChangedThreadIds.formUnion(recoveredIds)
                            changed = true
                        }
                        continue
                    }
                    // Title doesn't indicate busy — check if the shell has child processes
                    // (agent running inside the shell wrapper, e.g. zsh -c 'claude ...')
                    if paneState.pid > 0, !(childrenByPid[paneState.pid]?.isEmpty ?? true) {
                        // Shell has children — but the agent could be idle at its prompt
                        // (e.g. Claude Code waiting for user input while still running as
                        // a child process of the wrapper shell).
                        if let content = await tmux.capturePane(sessionName: session),
                           isAgentIdleAtPrompt(content) {
                            if threads[i].busySessions.contains(session) {
                                threads[i].busySessions.remove(session)
                                changed = true
                                busyChangedThreadIds.insert(threads[i].id)
                            }
                        } else {
                            if !threads[i].busySessions.contains(session) {
                                threads[i].busySessions.insert(session)
                                changed = true
                                busyChangedThreadIds.insert(threads[i].id)
                            }
                            let recoveredIds = clearRateLimitAfterRecovery(threadIndex: i, sessionName: session)
                            if !recoveredIds.isEmpty {
                                rateLimitChangedThreadIds.formUnion(recoveredIds)
                                changed = true
                            }
                        }
                        continue
                    }
                    // Agent not running — clear busy and waiting if set
                    if threads[i].busySessions.contains(session) {
                        threads[i].busySessions.remove(session)
                        changed = true
                        busyChangedThreadIds.insert(threads[i].id)
                    }
                    if threads[i].waitingForInputSessions.contains(session) {
                        threads[i].waitingForInputSessions.remove(session)
                        notifiedWaitingSessions.remove(session)
                        changed = true
                        busyChangedThreadIds.insert(threads[i].id)
                    }
                } else {
                    // Non-shell process running (e.g. node, claude, or a version string
                    // like "2.1.63" that Claude Code sets as its process title).
                    // Skip if a completion bell was recently received for this session;
                    // the bell fires just before the process exits, so pane_current_command
                    // can still show the agent binary for a brief window after completion.
                    let recentlyCompleted: Bool = {
                        guard let bellDate = recentBellBySession[session] else { return false }
                        return Date().timeIntervalSince(bellDate) < 5.0
                    }()
                    if !recentlyCompleted && !threads[i].waitingForInputSessions.contains(session) {
                        // The agent process can still be the foreground command even when
                        // idle at its prompt (e.g. Claude Code showing ❯). Verify via
                        // pane content that the agent is actually working.
                        if let content = await tmux.capturePane(sessionName: session),
                           isAgentIdleAtPrompt(content) {
                            if threads[i].busySessions.contains(session) {
                                threads[i].busySessions.remove(session)
                                changed = true
                                busyChangedThreadIds.insert(threads[i].id)
                            }
                        } else {
                            if !threads[i].busySessions.contains(session) {
                                threads[i].busySessions.insert(session)
                                changed = true
                                busyChangedThreadIds.insert(threads[i].id)
                            }
                            let recoveredIds = clearRateLimitAfterRecovery(threadIndex: i, sessionName: session)
                            if !recoveredIds.isEmpty {
                                rateLimitChangedThreadIds.formUnion(recoveredIds)
                                changed = true
                            }
                        }
                    }
                }
            }
        }

        if changed {
            await MainActor.run {
                delegate?.threadManager(self, didUpdateThreads: threads)
                for threadId in busyChangedThreadIds {
                    if let thread = threads.first(where: { $0.id == threadId }) {
                        postBusySessionsChangedNotification(for: thread)
                    }
                }
                for threadId in rateLimitChangedThreadIds {
                    NotificationCenter.default.post(
                        name: .magentAgentRateLimitChanged,
                        object: self,
                        userInfo: ["threadId": threadId]
                    )
                }
            }
            await publishRateLimitSummaryIfNeeded()
        }
    }

    // MARK: - Pane Analysis

    func paneTitleIndicatesBusy(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let scalar = trimmed.unicodeScalars.first else { return false }
        let v = scalar.value
        // Braille spinner (⠋⠙⠹…) used by Claude Code / Codex while processing.
        if (0x2800...0x28FF).contains(v) { return true }
        // ✳ (U+2733 eight-spoked asterisk) — alternate busy prefix used by Claude Code.
        if v == 0x2733 { return true }
        return false
    }

    /// Checks whether the agent appears to be idle at its input prompt by looking
    /// at the pane content. The definitive busy signal is the "esc to interrupt"
    /// status bar text that Claude Code shows while processing. If that text is
    /// present, the agent is busy. If a ❯ prompt is visible without
    /// "esc to interrupt", the agent is idle (even if the user has typed text
    /// at the prompt but hasn't submitted it yet).
    func isAgentIdleAtPrompt(_ paneContent: String) -> Bool {
        let lines = paneContent.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let nonEmpty = lines.suffix(15)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // "esc to interrupt" is shown in the status bar while Claude processes
        // → definitely busy, regardless of prompt visibility.
        // However, in permission bypass mode the status bar reads
        // "⏵⏵ bypass permissions on (shift+tab to cycle) · esc to interrupt"
        // even when the agent is idle. Exclude those lines so the bypass-mode
        // status text doesn't cause a false busy detection.
        let hasBusyIndicator = nonEmpty.contains(where: {
            $0.contains("esc to interrupt") && !$0.contains("bypass")
        })
        if hasBusyIndicator {
            return false
        }

        // ❯ prompt visible without the busy status bar → agent is idle
        let hasPrompt = nonEmpty.contains(where: { $0.hasPrefix("\u{276F}") })
        return hasPrompt
    }
}
