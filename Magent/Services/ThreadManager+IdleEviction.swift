import Foundation
import MagentCore

extension ThreadManager {

    /// Evicts the oldest idle tmux sessions when the total live session count
    /// exceeds `AppSettings.maxIdleSessions`.  Only sessions that have been
    /// idle for at least 1 minute and not visited for at least 1 hour are
    /// eligible.  Main-thread sessions and the currently selected session are
    /// always exempt.
    func evictIdleSessionsIfNeeded() async {
        let settings = persistence.loadSettings()
        guard let maxIdle = settings.maxIdleSessions else { return }

        // Gather all live tmux sessions referenced by non-archived threads.
        let liveSessions: Set<String>
        do {
            liveSessions = Set(try await tmux.listSessions())
        } catch {
            return
        }

        // Build a flat list of (sessionName, threadId, isMain) for all referenced live sessions.
        struct SessionInfo {
            let sessionName: String
            let threadId: UUID
            let isMain: Bool
        }

        var allSessions: [SessionInfo] = []
        for thread in threads where !thread.isArchived {
            for session in thread.tmuxSessionNames where liveSessions.contains(session) {
                allSessions.append(SessionInfo(
                    sessionName: session,
                    threadId: thread.id,
                    isMain: thread.isMain
                ))
            }
        }

        let liveCount = allSessions.count
        guard liveCount > maxIdle else { return }

        let now = Date()
        let minIdleDuration: TimeInterval = 60          // 1 minute since last busy
        let minUnvisitedDuration: TimeInterval = 3600    // 1 hour since last visit

        // Find the currently visible session so we never evict it.
        let currentSession: String? = {
            guard let activeId = activeThreadId,
                  let thread = threads.first(where: { $0.id == activeId }) else { return nil }
            return thread.lastSelectedTabIdentifier
        }()

        // Filter to eviction candidates.
        var candidates: [(session: String, lastVisited: Date)] = []
        for info in allSessions {
            // Never evict main-thread sessions.
            if info.isMain { continue }

            // Never evict the currently visible session.
            if info.sessionName == currentSession { continue }

            // Never evict already-evicted sessions (shouldn't be live, but be safe).
            if evictedIdleSessions.contains(info.sessionName) { continue }

            // Skip sessions that are currently busy.
            if let thread = threads.first(where: { $0.id == info.threadId }),
               thread.busySessions.contains(info.sessionName) { continue }

            // Skip sessions that were busy within the last minute.
            if let lastBusy = sessionLastBusyAt[info.sessionName],
               now.timeIntervalSince(lastBusy) < minIdleDuration { continue }

            // Skip sessions visited within the last hour.
            let lastVisited = sessionLastVisitedAt[info.sessionName] ?? .distantPast
            if now.timeIntervalSince(lastVisited) < minUnvisitedDuration { continue }

            // Also skip sessions that are waiting for input (user action needed).
            if let thread = threads.first(where: { $0.id == info.threadId }),
               thread.waitingForInputSessions.contains(info.sessionName) { continue }

            candidates.append((info.sessionName, lastVisited))
        }

        guard !candidates.isEmpty else { return }

        // Sort: oldest visit first.
        candidates.sort { $0.lastVisited < $1.lastVisited }

        let excessCount = liveCount - maxIdle
        let toEvict = candidates.prefix(excessCount)
        guard !toEvict.isEmpty else { return }

        for candidate in toEvict {
            NSLog("[IdleEviction] Evicting idle session: \(candidate.session) (last visited: \(candidate.lastVisited))")
            evictedIdleSessions.insert(candidate.session)
            try? await tmux.killSession(name: candidate.session)
        }

        NSLog("[IdleEviction] Evicted \(toEvict.count) idle session(s), live count was \(liveCount), limit \(maxIdle)")
    }
}
