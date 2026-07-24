import Foundation
import Testing

@Suite
@MainActor
struct ArchiveCurrentThreadScriptTests {

    @Test
    func concurrentWorkflowsSerializeMergeAndArchiveInOneRepository() throws {
        let fixture = try ArchiveScriptFixture()
        defer { fixture.remove() }

        let first = fixture.makeArchiveProcess(threadName: "one")
        let second = fixture.makeArchiveProcess(threadName: "two")

        try first.process.run()
        try second.process.run()
        first.process.waitUntilExit()
        second.process.waitUntilExit()

        #expect(first.process.terminationStatus == 0)
        #expect(second.process.terminationStatus == 0)
        #expect(!FileManager.default.fileExists(atPath: fixture.overlapFile.path))
        #expect(try fixture.gitOutput(["status", "--porcelain"], in: fixture.mainWorktree).isEmpty)

        try fixture.runGit(["merge-base", "--is-ancestor", "branch-one", "main"], in: fixture.mainWorktree)
        try fixture.runGit(["merge-base", "--is-ancestor", "branch-two", "main"], in: fixture.mainWorktree)

        let combinedOutput = first.output + second.output
        #expect(combinedOutput.contains("currently archiving '"))
        #expect(combinedOutput.contains("is position 2 of 2"))
        #expect(combinedOutput.contains("1 ahead"))

        let events = try String(contentsOf: fixture.eventLog, encoding: .utf8)
            .split(separator: "\n")
            .map(String.init)
        var archiveIsActive = false
        for event in events {
            if event.hasPrefix("archive-start ") {
                #expect(!archiveIsActive)
                archiveIsActive = true
            } else if event.hasPrefix("archive-end ") {
                #expect(archiveIsActive)
                archiveIsActive = false
            } else if event.hasPrefix("merge-start ") {
                #expect(!archiveIsActive)
            }
        }
        #expect(!archiveIsActive)
        #expect(events.filter { $0.hasPrefix("merge-start ") }.count == 2)
        #expect(events.filter { $0.hasPrefix("archive-start ") }.count == 2)

        let queueContents = try FileManager.default.contentsOfDirectory(
            at: fixture.queueDirectory,
            includingPropertiesForKeys: nil
        )
        #expect(!queueContents.contains { $0.lastPathComponent.hasPrefix("request-") })
        #expect(!queueContents.contains { $0.lastPathComponent == "active.json" })
    }
}

@MainActor
private struct CapturedArchiveProcess {
    let process: Process
    let outputPipe: Pipe

    var output: String {
        String(
            data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }
}

@MainActor
private final class ArchiveScriptFixture {
    let root: URL
    let mainWorktree: URL
    let eventLog: URL
    let overlapFile: URL

    var queueDirectory: URL {
        mainWorktree.appendingPathComponent(".git/magent-archive-queue", isDirectory: true)
    }

    private let fakeBin: URL
    private let mergeProbe: URL
    private let scriptURL: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-archive-script-\(UUID().uuidString)", isDirectory: true)
        mainWorktree = root.appendingPathComponent("main", isDirectory: true)
        fakeBin = root.appendingPathComponent("bin", isDirectory: true)
        eventLog = root.appendingPathComponent("events.log")
        overlapFile = root.appendingPathComponent("merge-overlap")
        mergeProbe = root.appendingPathComponent("merge-probe", isDirectory: true)
        scriptURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("scripts/archive-current-thread.sh")

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fakeBin, withIntermediateDirectories: true)
        try setupRepository()
        try writeFakeGit()
        try writeFakeMagentCLI()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }

    func makeArchiveProcess(threadName: String) -> CapturedArchiveProcess {
        let process = Process()
        let outputPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [
            scriptURL.path,
            "--thread", threadName,
            "--no-push",
            "--skip-local-sync",
        ]
        process.environment = fixtureEnvironment
        process.standardOutput = outputPipe
        process.standardError = FileHandle.nullDevice
        return CapturedArchiveProcess(process: process, outputPipe: outputPipe)
    }

    func runGit(_ arguments: [String], in directory: URL) throws {
        _ = try runProcess("/usr/bin/git", arguments: arguments, in: directory)
    }

    func gitOutput(_ arguments: [String], in directory: URL) throws -> String {
        try runProcess("/usr/bin/git", arguments: arguments, in: directory)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var fixtureEnvironment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "\(fakeBin.path):/usr/bin:/bin:/usr/sbin:/sbin"
        environment["MAGENT_CLI_PATH"] = fakeBin.appendingPathComponent("magent-cli").path
        environment["ARCHIVE_TEST_ROOT"] = root.path
        environment["ARCHIVE_TEST_EVENT_LOG"] = eventLog.path
        environment["ARCHIVE_TEST_MERGE_PROBE"] = mergeProbe.path
        environment["ARCHIVE_TEST_OVERLAP_FILE"] = overlapFile.path
        environment["GIT_EDITOR"] = "true"
        environment["GIT_MERGE_AUTOEDIT"] = "no"
        environment["MAGENT_ARCHIVE_HEARTBEAT_SECONDS"] = "1"
        environment["MAGENT_ARCHIVE_POLL_SECONDS"] = "1"
        return environment
    }

    private func setupRepository() throws {
        try runGit(["init", "--initial-branch=main", mainWorktree.path], in: root)
        try runGit(["config", "user.name", "Magent Test"], in: mainWorktree)
        try runGit(["config", "user.email", "magent-test@example.com"], in: mainWorktree)

        try "base\n".write(
            to: mainWorktree.appendingPathComponent("base.txt"),
            atomically: true,
            encoding: .utf8
        )
        try runGit(["add", "base.txt"], in: mainWorktree)
        try runGit(["commit", "-m", "Initial"], in: mainWorktree)

        for threadName in ["one", "two"] {
            let branchName = "branch-\(threadName)"
            let worktree = root.appendingPathComponent(threadName, isDirectory: true)
            try runGit(["branch", branchName, "main"], in: mainWorktree)
            try runGit(["worktree", "add", worktree.path, branchName], in: mainWorktree)
            try "\(threadName)\n".write(
                to: worktree.appendingPathComponent("\(threadName).txt"),
                atomically: true,
                encoding: .utf8
            )
            try runGit(["add", "\(threadName).txt"], in: worktree)
            try runGit(["commit", "-m", "Add \(threadName)"], in: worktree)
        }
    }

    private func writeFakeGit() throws {
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail

        is_merge=0
        for argument in "$@"; do
          if [[ "$argument" == "merge" ]]; then
            is_merge=1
            break
          fi
        done

        if [[ "$is_merge" -eq 0 ]]; then
          exec /usr/bin/git "$@"
        fi

        if ! mkdir "$ARCHIVE_TEST_MERGE_PROBE" 2>/dev/null; then
          touch "$ARCHIVE_TEST_OVERLAP_FILE"
        fi
        printf 'merge-start %s\\n' "$*" >> "$ARCHIVE_TEST_EVENT_LOG"
        sleep 0.25
        set +e
        /usr/bin/git "$@"
        status=$?
        set -e
        printf 'merge-end %s\\n' "$*" >> "$ARCHIVE_TEST_EVENT_LOG"
        rmdir "$ARCHIVE_TEST_MERGE_PROBE" 2>/dev/null || true
        exit "$status"
        """
        try writeExecutable(script, to: fakeBin.appendingPathComponent("git"))
    }

    private func writeFakeMagentCLI() throws {
        let script = """
        #!/usr/bin/env bash
        set -euo pipefail

        case "${1:-}" in
          thread-info)
            thread_name="${3:-}"
            printf '{"ok":true,"thread":{"projectName":"fixture","name":"%s","worktreePath":"%s/%s","isMain":false,"status":{"branchName":"branch-%s","baseBranch":"main"}}}\\n' "$thread_name" "$ARCHIVE_TEST_ROOT" "$thread_name" "$thread_name"
            ;;
          archive-thread)
            thread_name="${3:-}"
            printf 'archive-start %s\\n' "$thread_name" >> "$ARCHIVE_TEST_EVENT_LOG"
            sleep 1.25
            printf 'archive-end %s\\n' "$thread_name" >> "$ARCHIVE_TEST_EVENT_LOG"
            printf '{"ok":true}\\n'
            ;;
          *)
            printf '{"ok":false}\\n'
            exit 1
            ;;
        esac
        """
        try writeExecutable(script, to: fakeBin.appendingPathComponent("magent-cli"))
    }

    private func writeExecutable(_ contents: String, to url: URL) throws {
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o755))],
            ofItemAtPath: url.path
        )
    }

    private func runProcess(
        _ executable: String,
        arguments: [String],
        in directory: URL
    ) throws -> String {
        let process = Process()
        let output = Pipe()
        let error = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = error
        try process.run()
        process.waitUntilExit()

        let stdout = String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
        guard process.terminationStatus == 0 else {
            let stderr = String(
                data: error.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
            throw ArchiveScriptFixtureError.commandFailed(
                "\(executable) \(arguments.joined(separator: " ")): \(stderr)"
            )
        }
        return stdout
    }
}

private enum ArchiveScriptFixtureError: Error {
    case commandFailed(String)
}
