import AppKit
import Foundation
import UserNotifications

extension ThreadManager {

    // MARK: - Waiting-for-Input Detection

    func checkForWaitingForInput() async {
        let settings = persistence.loadSettings()
        let playSound = settings.playSoundForAgentCompletion
        var changed = false
        var changedThreadIds = Set<UUID>()
        var notifyPairs: [(threadIndex: Int, sessionName: String)] = []

        for i in threads.indices {
            guard !threads[i].isArchived else { continue }
            for session in threads[i].agentTmuxSessions {
                let wasWaiting = threads[i].waitingForInputSessions.contains(session)
                let isBusy = threads[i].busySessions.contains(session)

                // Only check busy sessions (or already-waiting sessions to detect resolution)
                guard isBusy || wasWaiting else { continue }

                guard let paneContent = await tmux.capturePane(sessionName: session) else { continue }
                let isWaiting = matchesWaitingForInputPattern(paneContent)

                if isWaiting && !wasWaiting {
                    // Transition: busy → waiting
                    threads[i].busySessions.remove(session)
                    threads[i].waitingForInputSessions.insert(session)
                    changed = true
                    changedThreadIds.insert(threads[i].id)

                    let isActiveThread = threads[i].id == activeThreadId
                    let isActiveTab = isActiveThread && threads[i].lastSelectedTmuxSessionName == session
                    if !isActiveTab && !notifiedWaitingSessions.contains(session) {
                        notifiedWaitingSessions.insert(session)
                        notifyPairs.append((i, session))
                    }
                } else if !isWaiting && wasWaiting {
                    // Transition: waiting → cleared (user provided input)
                    threads[i].waitingForInputSessions.remove(session)
                    notifiedWaitingSessions.remove(session)
                    changed = true
                    changedThreadIds.insert(threads[i].id)
                    // syncBusy will re-mark as busy on the same tick
                }
            }
        }

        guard changed else { return }
        for (threadIndex, sessionName) in notifyPairs {
            let projectName = settings.projects.first(where: { $0.id == threads[threadIndex].projectId })?.name ?? "Project"
            sendAgentWaitingNotification(for: threads[threadIndex], projectName: projectName, playSound: playSound, sessionName: sessionName)
        }

        await MainActor.run {
            updateDockBadge()
            delegate?.threadManager(self, didUpdateThreads: threads)
            for threadId in changedThreadIds {
                if let thread = threads.first(where: { $0.id == threadId }) {
                    postBusySessionsChangedNotification(for: thread)
                }
            }
            for i in threads.indices where !threads[i].isArchived && threads[i].hasWaitingForInput {
                NotificationCenter.default.post(
                    name: .magentAgentWaitingForInput,
                    object: self,
                    userInfo: [
                        "threadId": threads[i].id,
                        "waitingSessions": threads[i].waitingForInputSessions
                    ]
                )
            }
        }
    }

    func matchesWaitingForInputPattern(_ text: String) -> Bool {
        // Trim trailing whitespace/newlines and look at the last non-empty lines
        let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        let trimmedLines = lines.suffix(20).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !trimmedLines.isEmpty else { return false }
        let lastChunk = trimmedLines.suffix(15).joined(separator: "\n")

        // Claude Code plan mode
        if lastChunk.contains("Would you like to proceed?") { return true }

        // Claude Code permission prompts
        if lastChunk.contains("Do you want to") && (lastChunk.contains("Yes") || lastChunk.contains("No")) { return true }

        // Codex approval prompts
        if lastChunk.contains("approve") && lastChunk.contains("deny") { return true }

        // Claude Code AskUserQuestion / interactive prompt: ❯ selector at line start
        // Only match when ❯ is at the start of a line (interactive selector indicator),
        // not just anywhere in terminal (e.g. Claude Code's input prompt character).
        let lastFew = trimmedLines.suffix(6)
        let hasSelectorAtLineStart = lastFew.contains { $0.hasPrefix("\u{276F}") }
        if hasSelectorAtLineStart && lastFew.contains(where: { $0.range(of: #"^\u{276F}?\s*\d+\."#, options: .regularExpression) != nil }) { return true }

        // Claude Code ExitPlanMode / plan approval prompt
        if lastChunk.contains("Do you want me to go ahead") { return true }

        return false
    }

    private func sendAgentWaitingNotification(for thread: MagentThread, projectName: String, playSound: Bool, sessionName: String) {
        let settings = persistence.loadSettings()

        if settings.showSystemBanners {
            let content = UNMutableNotificationContent()
            content.title = "Agent Needs Input"
            content.body = "\(projectName) · \(thread.name)"
            if playSound {
                content.sound = UNNotificationSound(named: UNNotificationSoundName(settings.agentCompletionSoundName))
            }
            content.userInfo = ["threadId": thread.id.uuidString, "sessionName": sessionName]

            let request = UNNotificationRequest(
                identifier: "magent-agent-waiting-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }

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

    // MARK: - Missing Worktree Detection

    func checkForMissingWorktrees() async {
        let candidates = threads.filter { !$0.isMain && !$0.isArchived }
        var pruneRepos = Set<String>()
        var archivedAny = false

        for thread in candidates {
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: thread.worktreePath, isDirectory: &isDir)
            guard !exists || !isDir.boolValue else { continue }

            let settings = persistence.loadSettings()
            if let project = settings.projects.first(where: { $0.id == thread.projectId }) {
                pruneRepos.insert(project.repoPath)
            }
            try? await archiveThread(thread)
            archivedAny = true
        }

        if archivedAny {
            let settings = persistence.loadSettings()
            if settings.playSoundForAgentCompletion {
                let soundName = settings.agentCompletionSoundName
                if let sound = NSSound(named: NSSound.Name(soundName)) {
                    sound.play()
                }
            }
        }

        for repoPath in pruneRepos {
            await git.pruneWorktrees(repoPath: repoPath)
        }
    }
}
