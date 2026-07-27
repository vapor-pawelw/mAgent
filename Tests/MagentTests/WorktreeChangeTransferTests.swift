import Foundation
import MagentCore
import Testing

@Suite(.serialized)
struct WorktreeChangeTransferTests {
    @Test
    func transferMovesChangesAndRollbackRestoresSourceWithIndexState() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try "staged\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute("git add tracked.txt", workingDirectory: fixture.source.path)
        try "untracked\n".write(
            to: fixture.source.appendingPathComponent("new.txt"),
            atomically: true,
            encoding: .utf8
        )

        let transfer = try #require(
            try await GitService.shared.prepareWorktreeChangeTransfer(
                sourceWorktreePath: fixture.source.path,
                destinationWorktreePath: fixture.destination.path
            )
        )
        try await GitService.shared.applyWorktreeChangeTransfer(transfer)

        let sourceWhileTransferred = await ShellExecutor.execute(
            "git status --porcelain",
            workingDirectory: fixture.source.path
        )
        let destinationStatus = await ShellExecutor.execute(
            "git status --porcelain",
            workingDirectory: fixture.destination.path
        )
        #expect(sourceWhileTransferred.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        #expect(destinationStatus.stdout.contains("M  tracked.txt"))
        #expect(destinationStatus.stdout.contains("?? new.txt"))

        try await GitService.shared.rollbackWorktreeChangeTransfer(transfer)

        let sourceStatus = await ShellExecutor.execute(
            "git status --porcelain",
            workingDirectory: fixture.source.path
        )
        #expect(sourceStatus.stdout.contains("M  tracked.txt"))
        #expect(sourceStatus.stdout.contains("?? new.txt"))
        #expect(
            try String(contentsOf: fixture.source.appendingPathComponent("tracked.txt"), encoding: .utf8)
                == "staged\n"
        )
    }

    @Test
    func destinationConflictRestoresSourceAndRemovesRecoveryStash() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try "source change\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute("git add tracked.txt", workingDirectory: fixture.source.path)
        try "destination change\n".write(
            to: fixture.destination.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute(
            "git add tracked.txt && git commit -m destination-change",
            workingDirectory: fixture.destination.path
        )

        let transfer = try #require(
            try await GitService.shared.prepareWorktreeChangeTransfer(
                sourceWorktreePath: fixture.source.path,
                destinationWorktreePath: fixture.destination.path
            )
        )
        await #expect(throws: (any Error).self) {
            try await GitService.shared.applyWorktreeChangeTransfer(transfer)
        }
        try await GitService.shared.rollbackWorktreeChangeTransfer(transfer)

        let sourceStatus = await ShellExecutor.execute(
            "git status --porcelain",
            workingDirectory: fixture.source.path
        )
        let stashList = await ShellExecutor.execute(
            "git stash list",
            workingDirectory: fixture.source.path
        )
        #expect(sourceStatus.stdout.contains("M  tracked.txt"))
        #expect(
            try String(contentsOf: fixture.source.appendingPathComponent("tracked.txt"), encoding: .utf8)
                == "source change\n"
        )
        #expect(stashList.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    @Test
    func preparedTransferAppliesUserChangesAfterDestinationSetup() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try "user edit\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute("git add tracked.txt", workingDirectory: fixture.source.path)

        let transfer = try #require(
            try await GitService.shared.prepareWorktreeChangeTransfer(
                sourceWorktreePath: fixture.source.path,
                destinationWorktreePath: fixture.destination.path
            )
        )
        try "local sync\n".write(
            to: fixture.destination.appendingPathComponent("local-only.txt"),
            atomically: true,
            encoding: .utf8
        )

        try await GitService.shared.applyWorktreeChangeTransfer(transfer)

        #expect(
            try String(contentsOf: fixture.destination.appendingPathComponent("tracked.txt"), encoding: .utf8)
                == "user edit\n"
        )
        #expect(
            try String(contentsOf: fixture.destination.appendingPathComponent("local-only.txt"), encoding: .utf8)
                == "local sync\n"
        )
        try await GitService.shared.rollbackWorktreeChangeTransfer(transfer)
    }

    @Test
    func interruptedMoveMarkerRetainsEnoughRecoveryIdentity() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try "recover me\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        let sourceThreadID = UUID()
        let destinationThreadID = UUID()
        let marker = GitService.tabMoveRecoveryMarker(
            sourceThreadID: sourceThreadID,
            destinationThreadID: destinationThreadID,
            sourceSessionName: "ma-project-main-codex",
            destinationThreadName: "pikachu"
        )
        let transfer = try #require(
            try await GitService.shared.prepareWorktreeChangeTransfer(
                sourceWorktreePath: fixture.source.path,
                destinationWorktreePath: fixture.destination.path,
                recoveryMarker: marker
            )
        )

        let interruptedMove = try #require(
            try await GitService.shared.interruptedTabMoves(repoPath: fixture.source.path).first
        )
        #expect(interruptedMove.stashCommit == transfer.stashCommit)
        #expect(interruptedMove.sourceThreadID == sourceThreadID)
        #expect(interruptedMove.destinationThreadID == destinationThreadID)
        #expect(interruptedMove.sourceSessionName == "ma-project-main-codex")
        #expect(interruptedMove.destinationThreadName == "pikachu")

        try await GitService.shared.rollbackWorktreeChangeTransfer(transfer)
        #expect(try await GitService.shared.interruptedTabMoves(repoPath: fixture.source.path).isEmpty)
    }

    @Test
    func restoringChangesKeepsRecoveryStashUntilCleanupIsExplicitlyConfirmed() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try "recover me\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        let transfer = try #require(
            try await GitService.shared.prepareWorktreeChangeTransfer(
                sourceWorktreePath: fixture.source.path,
                destinationWorktreePath: fixture.destination.path
            )
        )

        try await GitService.shared.restoreWorktreeChangeTransfer(transfer)

        let restoredStatus = await ShellExecutor.execute(
            "git status --porcelain",
            workingDirectory: fixture.source.path
        )
        let stashBeforeCleanup = await ShellExecutor.execute(
            "git stash list --format=%H",
            workingDirectory: fixture.source.path
        )
        #expect(restoredStatus.stdout.contains("tracked.txt"))
        #expect(stashBeforeCleanup.stdout.contains(transfer.stashCommit))

        try await GitService.shared.finishWorktreeChangeTransfer(transfer)

        let stashAfterCleanup = await ShellExecutor.execute(
            "git stash list --format=%H",
            workingDirectory: fixture.source.path
        )
        #expect(!stashAfterCleanup.stdout.contains(transfer.stashCommit))
    }

    @Test
    func dirtySubmoduleNeverReusesAnOlderUnrelatedStash() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        try "older stash\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute(
            "git stash push --message older-unrelated-stash",
            workingDirectory: fixture.source.path
        )
        let olderStash = await ShellExecutor.execute(
            "git rev-parse refs/stash",
            workingDirectory: fixture.source.path
        )

        let submodule = fixture.root.appendingPathComponent("submodule", isDirectory: true)
        try FileManager.default.createDirectory(at: submodule, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: submodule.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: submodule.path)
        _ = await ShellExecutor.execute(
            "git config user.email magent-tests@example.com",
            workingDirectory: submodule.path
        )
        try "initial\n".write(
            to: submodule.appendingPathComponent("nested.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute(
            "git add nested.txt && git commit -m initial",
            workingDirectory: submodule.path
        )
        _ = await ShellExecutor.execute(
            "git -c protocol.file.allow=always submodule add \(shellQuoteForTest(submodule.path)) module && git commit -m add-submodule",
            workingDirectory: fixture.source.path
        )
        try "dirty nested repository\n".write(
            to: fixture.source.appendingPathComponent("module/nested.txt"),
            atomically: true,
            encoding: .utf8
        )
        try "ordinary edit\n".write(
            to: fixture.source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )

        await #expect(throws: (any Error).self) {
            try await GitService.shared.prepareWorktreeChangeTransfer(
                sourceWorktreePath: fixture.source.path,
                destinationWorktreePath: fixture.destination.path
            )
        }

        let currentStash = await ShellExecutor.execute(
            "git rev-parse refs/stash",
            workingDirectory: fixture.source.path
        )
        #expect(currentStash.stdout == olderStash.stdout)
        #expect(
            try String(contentsOf: fixture.source.appendingPathComponent("tracked.txt"), encoding: .utf8)
                == "ordinary edit\n"
        )
        #expect(
            try String(
                contentsOf: fixture.source.appendingPathComponent("module/nested.txt"),
                encoding: .utf8
            ) == "dirty nested repository\n"
        )
    }

    private func makeFixture() async throws -> (root: URL, source: URL, destination: URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-tab-move-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("repo", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: source.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: source.path)
        _ = await ShellExecutor.execute(
            "git config user.email magent-tests@example.com",
            workingDirectory: source.path
        )
        try "initial\n".write(
            to: source.appendingPathComponent("tracked.txt"),
            atomically: true,
            encoding: .utf8
        )
        _ = await ShellExecutor.execute(
            "git add tracked.txt && git commit -m initial",
            workingDirectory: source.path
        )
        _ = try await GitService.shared.createWorktree(
            repoPath: source.path,
            branchName: "destination",
            worktreePath: destination.path,
            baseBranch: "main"
        )
        return (root, source, destination)
    }

    private func shellQuoteForTest(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
