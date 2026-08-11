import Foundation
import MagentCore  // AgentType for lastRuntimeDetectedAgentBySession

struct SessionTerminationDrain {
    private var attemptedSessionNames = Set<String>()

    mutating func takePending(from sessionNames: [String]) -> [String] {
        sessionNames.filter { attemptedSessionNames.insert($0).inserted }
    }
}

enum AsyncSessionStateReconciler {
    static func applyingRenameMap(_ renameMap: [String: String], to currentSessionNames: [String]) -> [String] {
        currentSessionNames.map { renameMap[$0] ?? $0 }
    }

    static func mergingDetectedAgentTypes(
        _ detectedTypes: [String: AgentType],
        into currentTypes: [String: AgentType],
        validSessions: Set<String>
    ) -> [String: AgentType] {
        var merged = currentTypes.filter { validSessions.contains($0.key) }
        for (sessionName, agentType) in detectedTypes
            where validSessions.contains(sessionName) && merged[sessionName] == nil {
            merged[sessionName] = agentType
        }
        return merged
    }
}

enum AgentSessionProcessState {
    private static let shellCommands: Set<String> = ["sh", "bash", "zsh", "fish", "ksh", "tcsh", "csh"]

    static func isShellOnly(paneCommand: String, childProcesses: [(pid: pid_t, args: String)]) -> Bool {
        let command = URL(fileURLWithPath: paneCommand).lastPathComponent
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            .lowercased()
        return shellCommands.contains(command) && childProcesses.isEmpty
    }
}

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

    /// How long a cached runtime-detected agent type is trusted when live detection
    /// transiently returns nil (e.g. pane command becomes xcodebuild while Claude runs tools).
    static let lastRuntimeDetectedAgentTTL: TimeInterval = 60

    var sessionLastVisitedAt: [String: Date] = [:]
    var sessionLastBusyAt: [String: Date] = [:]
    var evictedIdleSessions: Set<String> = []
    var sessionsBeingRecreated: Set<String> = []
    var knownGoodSessionContexts: [String: KnownGoodSessionContext] = [:]
    var rendererUnhealthySessions: Set<String> = []
    var replayCorruptedSessions: Set<String> = []
    private let shellOnlyAgentSessionsLock = NSLock()
    private var shellOnlyAgentSessions: Set<String> = []

    func shellOnlyAgentSessionsSnapshot() -> Set<String> {
        shellOnlyAgentSessionsLock.withLock { shellOnlyAgentSessions }
    }

    func replaceShellOnlyAgentSessions(with sessions: Set<String>) -> Bool {
        shellOnlyAgentSessionsLock.withLock {
            guard shellOnlyAgentSessions != sessions else { return false }
            shellOnlyAgentSessions = sessions
            return true
        }
    }

    func rekeyShellOnlyAgentSession(from oldName: String, to newName: String) -> Bool {
        shellOnlyAgentSessionsLock.withLock {
            guard shellOnlyAgentSessions.remove(oldName) != nil else { return false }
            shellOnlyAgentSessions.insert(newName)
            return true
        }
    }

    /// Caches the last runtime-detected agent type per session. When `ps` child-process
    /// detection transiently fails (e.g. Claude reports its version as `pane_current_command`
    /// instead of "claude"), this prevents the session from flipping to `nil` and losing busy state.
    /// Entries expire after `lastRuntimeDetectedAgentTTL` seconds of consecutive nil detections.
    var lastRuntimeDetectedAgentBySession: [String: (agent: AgentType, detectedAt: Date)] = [:]

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
            lastRuntimeDetectedAgentBySession.removeValue(forKey: name)
            rendererUnhealthySessions.remove(name)
            replayCorruptedSessions.remove(name)
            _ = shellOnlyAgentSessionsLock.withLock {
                shellOnlyAgentSessions.remove(name)
            }
        }
    }

    func seedVisitTimestamps(for sessionNames: [String], at date: Date = Date()) {
        for name in sessionNames {
            sessionLastVisitedAt[name] = date
        }
    }
}
