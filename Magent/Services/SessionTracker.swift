import Foundation
import MagentCore

/// Metadata cached after verifying a session belongs to its expected thread/path context.
/// Avoids re-querying tmux on every `ensureSessionPrepared` call when nothing has changed.
struct KnownGoodSessionContext {
    let threadId: UUID
    let expectedPath: String
    let projectPath: String
    let isAgentSession: Bool
    let validatedAt: Date
}

/// Tracks transient per-session lifecycle state shared across multiple services.
/// Extracted from ThreadManager to decouple session tracking from thread management.
final class SessionTracker {

    var sessionLastVisitedAt: [String: Date] = [:]
    var sessionLastBusyAt: [String: Date] = [:]
    var evictedIdleSessions: Set<String> = []
    var sessionsBeingRecreated: Set<String> = []
    var knownGoodSessionContexts: [String: KnownGoodSessionContext] = [:]

    // MARK: - Convenience

    func markVisited(_ sessionName: String) {
        sessionLastVisitedAt[sessionName] = Date()
    }

    func markBusy(_ sessionName: String) {
        sessionLastBusyAt[sessionName] = Date()
    }

    func markEvicted(_ sessionName: String) {
        evictedIdleSessions.insert(sessionName)
    }

    func clearEviction(_ sessionName: String) {
        evictedIdleSessions.remove(sessionName)
    }

    func isEvicted(_ sessionName: String) -> Bool {
        evictedIdleSessions.contains(sessionName)
    }

    func cleanupForThread(sessionNames: [String]) {
        for name in sessionNames {
            sessionLastVisitedAt.removeValue(forKey: name)
            sessionLastBusyAt.removeValue(forKey: name)
            evictedIdleSessions.remove(name)
            sessionsBeingRecreated.remove(name)
            knownGoodSessionContexts.removeValue(forKey: name)
        }
    }

    func seedVisitTimestamps(for sessionNames: [String], at date: Date = Date()) {
        for name in sessionNames {
            sessionLastVisitedAt[name] = date
        }
    }
}
