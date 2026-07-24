import Foundation
import MagentCore
import Testing

@Suite
struct TerminalSurfaceReuseIdentityTests {
    @Test
    func stableIdentityMatchesForEquivalentPaths() {
        let threadID = UUID()
        let createdAt = Date(timeIntervalSince1970: 10)

        let first = TerminalSurfaceReuseIdentity(
            threadID: threadID,
            sessionName: "ma-thread-codex",
            worktreePath: "/tmp/project/../project/thread",
            isAgentSession: true,
            agentType: .codex,
            sessionCreatedAt: createdAt
        )
        let second = TerminalSurfaceReuseIdentity(
            threadID: threadID,
            sessionName: "ma-thread-codex",
            worktreePath: "/tmp/project/thread",
            isAgentSession: true,
            agentType: .codex,
            sessionCreatedAt: createdAt
        )

        #expect(first.cacheKey == second.cacheKey)
    }

    @Test
    func identityChangesWhenSessionOwnershipChanges() {
        let base = TerminalSurfaceReuseIdentity(
            threadID: UUID(),
            sessionName: "ma-thread",
            worktreePath: "/tmp/thread",
            isAgentSession: false,
            agentType: nil,
            sessionCreatedAt: Date(timeIntervalSince1970: 10)
        )
        let recreated = TerminalSurfaceReuseIdentity(
            threadID: base.threadID,
            sessionName: base.sessionName,
            worktreePath: base.worktreePath,
            isAgentSession: false,
            agentType: nil,
            sessionCreatedAt: Date(timeIntervalSince1970: 11)
        )

        #expect(base.cacheKey != recreated.cacheKey)
    }
}
