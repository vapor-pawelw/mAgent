import Foundation
import MagentCore
import Testing

@Suite
struct GitServiceUntrackedDirectoryTests {
    @Test
    func untrackedFilesUnderDirectoryListsNonIgnoredChildren() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init", workingDirectory: root.path)

        let directory = root.appendingPathComponent("NewFolder", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Nested", isDirectory: true),
            withIntermediateDirectories: true
        )
        try "keep\n".write(to: directory.appendingPathComponent("A.txt"), atomically: true, encoding: .utf8)
        try "nested\n".write(
            to: directory.appendingPathComponent("Nested/B.swift"),
            atomically: true,
            encoding: .utf8
        )
        try "ignored\n".write(
            to: directory.appendingPathComponent("ignored.log"),
            atomically: true,
            encoding: .utf8
        )
        try "*.log\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)

        let files = await GitService.shared.untrackedFiles(
            worktreePath: root.path,
            under: "NewFolder/"
        )

        #expect(files == [
            "NewFolder/A.txt",
            "NewFolder/Nested/B.swift",
        ])
    }

    @Test
    func workingTreeDiffExpandsUntrackedDirectoriesIntoNestedFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: root.path)

        try "tracked\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add tracked.txt && git commit -m initial", workingDirectory: root.path)

        let nestedDirectory = root.appendingPathComponent("Sources/Feature", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDirectory, withIntermediateDirectories: true)
        let deeperDirectory = nestedDirectory.appendingPathComponent("Presentation", isDirectory: true)
        try FileManager.default.createDirectory(at: deeperDirectory, withIntermediateDirectories: true)
        try "view\n".write(to: nestedDirectory.appendingPathComponent("View.swift"), atomically: true, encoding: .utf8)
        try "model\n".write(to: nestedDirectory.appendingPathComponent("Model.swift"), atomically: true, encoding: .utf8)
        try "screen\n".write(to: deeperDirectory.appendingPathComponent("Screen.swift"), atomically: true, encoding: .utf8)

        let stats = await GitService.shared.workingTreeDiffStats(worktreePath: root.path)
        let content = await GitService.shared.workingTreeDiffContent(worktreePath: root.path)

        #expect(stats.map(\.relativePath) == [
            "Sources/Feature/Model.swift",
            "Sources/Feature/Presentation/Screen.swift",
            "Sources/Feature/View.swift",
        ])
        #expect(content?.contains("diff --git a/Sources/Feature/Model.swift b/Sources/Feature/Model.swift") == true)
        #expect(content?.contains("diff --git a/Sources/Feature/Presentation/Screen.swift b/Sources/Feature/Presentation/Screen.swift") == true)
        #expect(content?.contains("diff --git a/Sources/Feature/View.swift b/Sources/Feature/View.swift") == true)
        #expect(content?.contains("diff --git a/Sources/ b/Sources/") == false)
    }

    @Test
    func threadDiffTabStatsCountsCommittedBranchChanges() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: root.path)

        try "one\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add tracked.txt && git commit -m initial", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git checkout -b feature", workingDirectory: root.path)
        try "one\ntwo\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add tracked.txt && git commit -m feature", workingDirectory: root.path)

        let workingTreeOnly = await GitService.shared.workingTreeDiffStats(worktreePath: root.path)
        let diffTabStats = await GitService.shared.threadDiffTabStats(worktreePath: root.path, baseBranch: "main")

        #expect(workingTreeOnly.isEmpty)
        #expect(diffTabStats.map(\.relativePath) == ["tracked.txt"])
    }

    @Test
    func commitDiffStatsAndContentReflectSpecificCommitOnly() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: root.path)

        try "one\n".write(to: root.appendingPathComponent("first.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add first.txt && git commit -m initial", workingDirectory: root.path)

        try "two\n".write(to: root.appendingPathComponent("second.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add second.txt && git commit -m second", workingDirectory: root.path)
        let commit = await ShellExecutor.execute("git rev-parse --short HEAD", workingDirectory: root.path)
        let commitHash = commit.stdout.trimmingCharacters(in: .whitespacesAndNewlines)

        try "uncommitted\n".write(
            to: root.appendingPathComponent("working-tree.txt"),
            atomically: true,
            encoding: .utf8
        )

        let stats = await GitService.shared.commitDiffStats(worktreePath: root.path, commitHash: commitHash)
        let content = await GitService.shared.commitDiffContent(worktreePath: root.path, commitHash: commitHash)

        #expect(stats.map(\.relativePath) == ["second.txt"])
        #expect(content?.contains("diff --git a/second.txt b/second.txt") == true)
        #expect(content?.contains("working-tree.txt") == false)
    }

    @Test
    func workingTreeDiffStatsMarksBinaryFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: root.path)

        let image = root.appendingPathComponent("image.bin")
        try Data([0, 1, 2, 3, 4, 5]).write(to: image)
        try "text\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add image.bin note.txt && git commit -m initial", workingDirectory: root.path)

        try Data([0, 1, 9, 3, 4, 5, 6]).write(to: image)
        try "text\nmore\n".write(to: root.appendingPathComponent("note.txt"), atomically: true, encoding: .utf8)

        let stats = await GitService.shared.workingTreeDiffStats(worktreePath: root.path)
        let binary = try #require(stats.first { $0.relativePath == "image.bin" })
        let text = try #require(stats.first { $0.relativePath == "note.txt" })

        #expect(binary.isBinary)
        #expect(binary.additions == 0)
        #expect(binary.deletions == 0)
        #expect(!text.isBinary)
        #expect(text.additions == 1)
    }

    @Test
    func workingTreeDiffContentSummarizesUntrackedBinaryFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: root.path)

        try "tracked\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add tracked.txt && git commit -m initial", workingDirectory: root.path)

        try Data([0, 1, 2, 3, 4, 5]).write(to: root.appendingPathComponent("untracked.bin"))

        let content = try #require(await GitService.shared.workingTreeDiffContent(worktreePath: root.path))

        #expect(content.contains("diff --git a/untracked.bin b/untracked.bin"))
        #expect(content.contains("Binary files /dev/null and b/untracked.bin differ"))
        #expect(!content.contains("@@ -0,0"))
    }

    @Test
    func workingTreeDiffContentSummarizesOversizedUntrackedTextFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-git-service-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        _ = await ShellExecutor.execute("git init -b main", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.name Magent Tests", workingDirectory: root.path)
        _ = await ShellExecutor.execute("git config user.email magent-tests@example.com", workingDirectory: root.path)

        try "tracked\n".write(to: root.appendingPathComponent("tracked.txt"), atomically: true, encoding: .utf8)
        _ = await ShellExecutor.execute("git add tracked.txt && git commit -m initial", workingDirectory: root.path)

        let largeText = String(repeating: "0123456789abcdef\n", count: 70_000)
        try largeText.write(to: root.appendingPathComponent("large.txt"), atomically: true, encoding: .utf8)

        let content = try #require(await GitService.shared.workingTreeDiffContent(worktreePath: root.path))

        #expect(content.contains("diff --git a/large.txt b/large.txt"))
        #expect(content.contains("Binary files /dev/null and b/large.txt differ"))
        #expect(!content.contains(String(repeating: "0123456789abcdef\n", count: 100)))
    }
}
