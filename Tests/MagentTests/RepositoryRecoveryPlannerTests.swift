import Foundation
import MagentCore
import Testing

@Suite
struct RepositoryRecoveryPlannerTests {
    @Test
    func remapsMainThreadToNewRepoPath() {
        let result = RepositoryRecoveryPlanner.remappedThreadWorktreePath(
            "/old/app",
            oldRepoPath: "/old/app",
            newRepoPath: "/new/app",
            oldWorktreesBasePath: "/old/.worktrees-app",
            newWorktreesBasePath: "/new/.worktrees-app"
        )

        #expect(result == "/new/app")
    }

    @Test
    func remapsThreadUnderOldWorktreesBase() {
        let result = RepositoryRecoveryPlanner.remappedThreadWorktreePath(
            "/old/.worktrees-app/feature-a",
            oldRepoPath: "/old/app",
            newRepoPath: "/new/app",
            oldWorktreesBasePath: "/old/.worktrees-app",
            newWorktreesBasePath: "/new/.worktrees-app"
        )

        #expect(result == "/new/.worktrees-app/feature-a")
    }

    @Test
    func leavesCustomThreadPathUnchanged() {
        let result = RepositoryRecoveryPlanner.remappedThreadWorktreePath(
            "/custom/worktrees/feature-a",
            oldRepoPath: "/old/app",
            newRepoPath: "/new/app",
            oldWorktreesBasePath: "/old/.worktrees-app",
            newWorktreesBasePath: "/new/.worktrees-app"
        )

        #expect(result == "/custom/worktrees/feature-a")
    }

    @Test
    func movesDefaultWorktreesBaseWithRepo() {
        let project = Project(
            name: "app",
            repoPath: "/old/app",
            worktreesBasePath: Project.suggestedWorktreesPath(for: "/old/app")
        )

        let result = RepositoryRecoveryPlanner.worktreesBasePath(
            oldProject: project,
            newRepoPath: "/new/app"
        )

        #expect(result == Project.suggestedWorktreesPath(for: "/new/app"))
    }

    @Test
    func preservesCustomWorktreesBase() {
        let project = Project(
            name: "app",
            repoPath: "/old/app",
            worktreesBasePath: "/custom/worktrees"
        )

        let result = RepositoryRecoveryPlanner.worktreesBasePath(
            oldProject: project,
            newRepoPath: "/new/app"
        )

        #expect(result == "/custom/worktrees")
    }
}
