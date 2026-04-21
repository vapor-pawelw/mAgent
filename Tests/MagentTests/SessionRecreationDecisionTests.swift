import Foundation
import Testing
import MagentCore

@Suite
struct SessionRecreationDecisionTests {

    // MARK: - path(_:isWithin:)

    @Test
    func pathEqualToRootIsWithin() {
        #expect(SessionRecreationService.path("/foo/bar", isWithin: "/foo/bar"))
    }

    @Test
    func pathNestedUnderRootIsWithin() {
        #expect(SessionRecreationService.path("/foo/bar/baz", isWithin: "/foo/bar"))
    }

    @Test
    func pathTrailingSlashOnRootIsNormalized() {
        #expect(SessionRecreationService.path("/foo/bar/baz", isWithin: "/foo/bar/"))
        #expect(SessionRecreationService.path("/foo/bar", isWithin: "/foo/bar/"))
    }

    @Test
    func pathPrefixButNotChildIsNotWithin() {
        // Subtle: "/foo" must not match "/foobar" — this is the bug the "+ /" suffix
        // check exists to prevent.
        #expect(!SessionRecreationService.path("/foobar", isWithin: "/foo"))
        #expect(!SessionRecreationService.path("/foo/barbaz", isWithin: "/foo/bar"))
    }

    @Test
    func pathUnrelatedRootIsNotWithin() {
        #expect(!SessionRecreationService.path("/other/path", isWithin: "/foo/bar"))
    }

    // MARK: - isShellCommand

    @Test
    func recognizedShellsReturnTrue() {
        for shell in ["sh", "bash", "zsh", "fish", "ksh", "tcsh", "csh"] {
            #expect(SessionRecreationService.isShellCommand(shell), "expected \(shell) to be a shell")
        }
    }

    @Test
    func nonShellCommandsReturnFalse() {
        #expect(!SessionRecreationService.isShellCommand("claude"))
        #expect(!SessionRecreationService.isShellCommand("vim"))
        #expect(!SessionRecreationService.isShellCommand("/bin/bash")) // path form, not bare name
        #expect(!SessionRecreationService.isShellCommand(""))
    }

    // MARK: - decideSessionMatch: owner thread ID gating

    @Test
    func matchRequiresOwnerThreadIDToEqualThreadIDWhenPresent() {
        let thread = makeThread()
        let snapshot = makeSnapshot(ownerThreadId: UUID().uuidString)
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func matchAcceptsSnapshotWithMatchingOwnerThreadID() {
        let thread = makeThread()
        let snapshot = makeSnapshot(
            ownerThreadId: thread.id.uuidString,
            projectPath: "/repo",
            worktreePath: thread.worktreePath
        )
        #expect(SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func snapshotOlderThanThreadCreatedAtIsRejectedForWorktreeReuse() {
        // Worktree-name reuse guard: if a tmux session was created before this
        // thread existed (empty ownerThreadID + old createdAt), it belongs to a
        // prior owner and must not be adopted.
        let threadCreatedAt = Date()
        let thread = makeThread(createdAt: threadCreatedAt)
        let snapshot = makeSnapshot(
            createdAt: threadCreatedAt.addingTimeInterval(-120),
            ownerThreadId: nil
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func snapshotWithinOneSecondOfThreadCreatedAtIsNotRejected() {
        // The `.addingTimeInterval(-1)` tolerance guards against clock jitter
        // when the session is created immediately after the thread.
        let threadCreatedAt = Date()
        let thread = makeThread(createdAt: threadCreatedAt)
        let snapshot = makeSnapshot(
            createdAt: threadCreatedAt.addingTimeInterval(-0.5),
            panePath: thread.worktreePath,
            ownerThreadId: nil
        )
        #expect(SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    // MARK: - decideSessionMatch: pane path containment

    @Test
    func panePathOutsideWorktreeRejectsAgentSession() {
        let thread = makeThread()
        let snapshot = makeSnapshot(
            panePath: "/somewhere/else",
            ownerThreadId: thread.id.uuidString
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func panePathOutsideWorktreeIsAcceptedForTerminalSessionInShell() {
        // Users often `cd` out of the worktree in terminal tabs — don't recreate
        // the session under them. The exception only applies when the pane is
        // sitting on a shell prompt.
        let thread = makeThread()
        let snapshot = makeSnapshot(
            panePath: "/somewhere/else",
            paneCommand: "zsh",
            ownerThreadId: thread.id.uuidString
        )
        #expect(SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func panePathOutsideWorktreeWithNonShellCommandRejectsTerminalSession() {
        let thread = makeThread()
        let snapshot = makeSnapshot(
            panePath: "/somewhere/else",
            paneCommand: "vim",
            ownerThreadId: thread.id.uuidString
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    // MARK: - decideSessionMatch: agent type mismatch

    @Test
    func envAgentTypeMismatchRejects() {
        let thread = makeThread()
        let snapshot = makeSnapshot(
            ownerThreadId: thread.id.uuidString,
            agentType: "codex",
            projectPath: "/repo",
            worktreePath: thread.worktreePath
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: .claude, detectedAgentType: nil
        ))
    }

    @Test
    func envAgentTypeWithWhitespaceAndCaseIsNormalized() {
        let thread = makeThread()
        let snapshot = makeSnapshot(
            ownerThreadId: thread.id.uuidString,
            agentType: "  CLAUDE \n",
            projectPath: "/repo",
            worktreePath: thread.worktreePath
        )
        #expect(SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: .claude, detectedAgentType: nil
        ))
    }

    @Test
    func detectedAgentTypeFallbackRejectsWhenEnvIsMissing() {
        // When the env var is missing/blank, the caller falls back to process
        // detection. A mismatch there also rejects.
        let thread = makeThread()
        let snapshot = makeSnapshot(
            ownerThreadId: thread.id.uuidString,
            projectPath: "/repo",
            worktreePath: thread.worktreePath
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: .claude, detectedAgentType: .codex
        ))
    }

    @Test
    func detectedAgentTypeFallbackAcceptsWhenDetectedIsNil() {
        // No way to tell what's running — don't reject just because we couldn't
        // detect. Recreation would be more disruptive than leaving it.
        let thread = makeThread()
        let snapshot = makeSnapshot(
            ownerThreadId: thread.id.uuidString,
            projectPath: "/repo",
            worktreePath: thread.worktreePath
        )
        #expect(SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: true, expectedAgentType: .claude, detectedAgentType: nil
        ))
    }

    // MARK: - decideSessionMatch: main vs non-main fallbacks

    @Test
    func mainThreadRejectsDivergentProjectPathEnv() {
        let thread = makeThread(isMain: true)
        let snapshot = makeSnapshot(
            ownerThreadId: thread.id.uuidString,
            projectPath: "/other/repo"
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func nonMainThreadRejectsDivergentWorktreeEnvEvenWhenPanePathMatches() {
        // MAGENT_WORKTREE pointing at a different path means this session was
        // provisioned for another thread — reject even if the pane happens to
        // sit inside the same directory tree.
        let thread = makeThread()
        let snapshot = makeSnapshot(
            panePath: thread.worktreePath,
            ownerThreadId: thread.id.uuidString,
            worktreePath: "/some/other/worktree"
        )
        #expect(!SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    @Test
    func emptySnapshotFallsThroughToAcceptWhenPanePathIsAbsent() {
        // A session with no useful metadata (no ownerThreadID, no panePath, no
        // env) defaults to "match" — the caller's owner/createdAt guards above
        // are the real gate.
        let thread = makeThread()
        let snapshot = makeSnapshot()
        #expect(SessionRecreationService.decideSessionMatch(
            snapshot: snapshot, thread: thread, projectPath: "/repo",
            isAgentSession: false, expectedAgentType: nil, detectedAgentType: nil
        ))
    }

    // MARK: - Helpers

    private func makeThread(
        createdAt: Date = Date(),
        isMain: Bool = false
    ) -> MagentThread {
        MagentThread(
            projectId: UUID(),
            name: "thread",
            worktreePath: "/repo-worktrees/thread",
            branchName: "branch",
            createdAt: createdAt,
            isMain: isMain
        )
    }

    private func makeSnapshot(
        createdAt: Date? = nil,
        sessionPath: String? = nil,
        panePath: String? = nil,
        paneCommand: String? = nil,
        ownerThreadId: String? = nil,
        agentType: String? = nil,
        projectPath: String? = nil,
        worktreePath: String? = nil
    ) -> TmuxService.SessionContextSnapshot {
        TmuxService.SessionContextSnapshot(
            createdAt: createdAt,
            sessionPath: sessionPath,
            panePath: panePath,
            paneCommand: paneCommand,
            ownerThreadId: ownerThreadId,
            agentType: agentType,
            projectPath: projectPath,
            worktreePath: worktreePath
        )
    }
}
