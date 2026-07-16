import MagentCore
import Testing

@Suite
struct ProjectSettingsSelectionResolverTests {
    @Test
    func selectedRowResolvesNewProjectInsteadOfPreviouslyDisplayedProject() {
        let first = Project(name: "First", repoPath: "/tmp/first", worktreesBasePath: "/tmp/first-worktrees")
        let second = Project(name: "Second", repoPath: "/tmp/second", worktreesBasePath: "/tmp/second-worktrees")

        let selected = ProjectSettingsSelectionResolver.project(at: 1, in: [first, second])

        #expect(selected?.id == second.id)
    }

    @Test
    func missingSelectionDoesNotResolveAProject() {
        let project = Project(name: "First", repoPath: "/tmp/first", worktreesBasePath: "/tmp/first-worktrees")

        #expect(ProjectSettingsSelectionResolver.project(at: -1, in: [project]) == nil)
    }
}
