import Foundation
import GhosttyBridge
import MagentCore

// MARK: - ThreadManager+SessionRecreation
// Thin forwarding layer to SessionRecreationService.
// Stale session cleanup and referencedMagentSessionNames stay forwarded to SessionLifecycleService.
extension ThreadManager {

    static let knownGoodSessionTTL: TimeInterval = SessionRecreationService.knownGoodSessionTTL

    func isSessionPreparedFastPath(
        sessionName: String,
        thread: MagentThread,
        hasReusableTerminalSurface: Bool = false
    ) -> Bool {
        sessionRecreationService.isSessionPreparedFastPath(
            sessionName: sessionName,
            thread: thread,
            hasReusableTerminalSurface: hasReusableTerminalSurface
        )
    }

    func recreateSessionIfNeeded(
        sessionName: String,
        thread: MagentThread,
        onAction: (@MainActor @Sendable (SessionRecreationAction?) -> Void)? = nil
    ) async -> Bool {
        let recreated = await sessionRecreationService.recreateSessionIfNeeded(
            sessionName: sessionName,
            thread: thread,
            onAction: onAction
        )
        if recreated, await tmux.hasSession(name: sessionName) {
            await MainActor.run {
                GhosttyAppManager.shared.restoreSurfacesAfterServerRestart(
                    liveTmuxSessions: [sessionName]
                )
            }
        }
        return recreated
    }

    func markSessionContextKnownGood(
        sessionName: String,
        threadId: UUID,
        expectedPath: String,
        projectPath: String,
        isAgentSession: Bool
    ) {
        sessionRecreationService.markSessionContextKnownGood(
            sessionName: sessionName,
            threadId: threadId,
            expectedPath: expectedPath,
            projectPath: projectPath,
            isAgentSession: isAgentSession
        )
    }

    // MARK: - Stale Session Cleanup
    // Forwarded to SessionLifecycleService (Phase 4).

    @discardableResult
    func cleanupStaleMagentSessions(minimumStaleAge: TimeInterval = 0, now: Date = Date()) async -> [String] {
        await sessionLifecycleService.cleanupStaleMagentSessions(minimumStaleAge: minimumStaleAge, now: now)
    }

    nonisolated static func cleanupStaleSessions(
        tmux: TmuxService,
        referencedSessions: Set<String>
    ) async {
        await SessionLifecycleService.cleanupStaleSessions(tmux: tmux, referencedSessions: referencedSessions)
    }

    func referencedMagentSessionNames() -> Set<String> {
        sessionLifecycleService.referencedMagentSessionNames()
    }
}
