import Foundation
import MagentCore
import Testing

@Suite
struct SelectedThreadJumpPresenterTests {
    @Test
    func mainThreadUsesMainWorktreeTitleInsteadOfRepoFolderName() {
        let thread = makeThread(
            isMain: true,
            worktreePath: "/Users/example/Projects/magent"
        )

        #expect(SelectedThreadJumpPresenter.title(for: thread) == "Main worktree")
    }

    @Test
    func nonMainThreadPrefersTaskDescription() {
        let thread = makeThread(
            taskDescription: "Fix sidebar jump label",
            worktreePath: "/Users/example/Projects/magent-worktrees/sidebar-label"
        )

        #expect(SelectedThreadJumpPresenter.title(for: thread) == "Fix sidebar jump label")
    }

    @Test
    func nonMainThreadFallsBackToWorktreeFolderName() {
        let thread = makeThread(
            worktreePath: "/Users/example/Projects/magent-worktrees/sidebar-label"
        )

        #expect(SelectedThreadJumpPresenter.title(for: thread) == "sidebar-label")
    }

    private func makeThread(
        isMain: Bool = false,
        taskDescription: String? = nil,
        worktreePath: String
    ) -> MagentThread {
        MagentThread(
            projectId: UUID(),
            name: isMain ? "main" : "sidebar-label",
            worktreePath: worktreePath,
            branchName: isMain ? "main" : "fix/sidebar-label",
            isMain: isMain,
            taskDescription: taskDescription
        )
    }
}
