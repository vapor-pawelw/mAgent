import Foundation
import MagentCore
import Testing

@Suite("Git repository identity")
struct GitRepositoryIdentityTests {
    @Test("Main checkout, linked worktree, and symlink share one repository identity")
    func resolvesAliasesToOneIdentity() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-repository-identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let repository = root.appendingPathComponent("repository", isDirectory: true)
        let worktree = root.appendingPathComponent("linked-worktree", isDirectory: true)
        let symlink = root.appendingPathComponent("repository-link", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("frontend"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: repository.appendingPathComponent("backend"),
            withIntermediateDirectories: true
        )
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: repository.path)
        _ = await ShellExecutor.execute("git config user.name 'Magent Tests'", workingDirectory: repository.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: repository.path)
        try "tracked\n".write(
            to: repository.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "frontend\n".write(
            to: repository.appendingPathComponent("frontend/package.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "backend\n".write(
            to: repository.appendingPathComponent("backend/package.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute("git add . && git commit -m initial", workingDirectory: repository.path)
        _ = try await GitService.shared.createWorktree(
            repoPath: repository.path,
            branchName: "feature/identity",
            worktreePath: worktree.path,
            baseBranch: "main"
        )
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: repository)

        let mainIdentity = try await GitService.shared.repositoryIdentity(at: repository.path)
        let worktreeIdentity = try await GitService.shared.repositoryIdentity(at: worktree.path)
        let symlinkIdentity = try await GitService.shared.repositoryIdentity(at: symlink.path)

        #expect(mainIdentity.commonDirectoryPath == worktreeIdentity.commonDirectoryPath)
        #expect(mainIdentity.commonDirectoryPath == symlinkIdentity.commonDirectoryPath)
        #expect(mainIdentity.primaryWorktreePath == repository.resolvingSymlinksInPath().standardizedFileURL.path)
        #expect(worktreeIdentity.primaryWorktreePath == mainIdentity.primaryWorktreePath)
        #expect(symlinkIdentity.primaryWorktreePath == mainIdentity.primaryWorktreePath)

        let mainFrontendIdentity = try await GitService.shared.repositoryIdentity(
            at: repository.appendingPathComponent("frontend").path
        )
        let worktreeFrontendIdentity = try await GitService.shared.repositoryIdentity(
            at: worktree.appendingPathComponent("frontend").path
        )
        let backendIdentity = try await GitService.shared.repositoryIdentity(
            at: repository.appendingPathComponent("backend").path
        )
        #expect(mainFrontendIdentity.projectIdentity == worktreeFrontendIdentity.projectIdentity)
        #expect(mainFrontendIdentity.canonicalProjectPath == repository.appendingPathComponent("frontend").path)
        #expect(mainFrontendIdentity.projectIdentity != backendIdentity.projectIdentity)
    }

    @Test("A bare-backed worktree remains its own stable canonical path")
    func preservesBareBackedWorktreePath() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-bare-repository-identity-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let source = root.appendingPathComponent("source", isDirectory: true)
        let bare = root.appendingPathComponent("repository.git", isDirectory: true)
        let firstWorktree = root.appendingPathComponent("first", isDirectory: true)
        let secondWorktree = root.appendingPathComponent("second", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: source.path)
        _ = await ShellExecutor.execute("git config user.name 'Magent Tests'", workingDirectory: source.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: source.path)
        try "tracked\n".write(
            to: source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute("git add . && git commit -m initial", workingDirectory: source.path)
        _ = await ShellExecutor.execute(
            "git clone --bare '\(source.path)' '\(bare.path)'",
            workingDirectory: root.path
        )
        _ = await ShellExecutor.execute(
            "git --git-dir='\(bare.path)' worktree add '\(firstWorktree.path)' main",
            workingDirectory: root.path
        )
        _ = await ShellExecutor.execute(
            "git --git-dir='\(bare.path)' worktree add -b feature/second '\(secondWorktree.path)' main",
            workingDirectory: root.path
        )

        let firstIdentity = try await GitService.shared.repositoryIdentity(at: firstWorktree.path)
        let secondIdentity = try await GitService.shared.repositoryIdentity(at: secondWorktree.path)

        #expect(firstIdentity.projectIdentity == secondIdentity.projectIdentity)
        #expect(firstIdentity.canonicalProjectPath == firstWorktree.path)
        #expect(secondIdentity.canonicalProjectPath == secondWorktree.path)
    }
}
