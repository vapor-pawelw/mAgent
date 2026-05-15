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
}
