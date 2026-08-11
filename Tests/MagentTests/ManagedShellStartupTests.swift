import Foundation
import Testing

@Suite("Managed shell startup")
struct ManagedShellStartupTests {
    @Test("Agent profile skips user shell files but keeps Magent behavior")
    func agentProfileIsIsolated() throws {
        let fixture = try ShellFixture()
        defer { fixture.remove() }
        let result = try fixture.run(profile: ManagedShellStartup.agentProfile)

        #expect(result.status == 0)
        #expect(result.output.contains("user-files=none"))
        #expect(result.output.contains("start-agent=function"))
        #expect(result.output.contains("cwd=\(fixture.worktree.path)"))
        #expect(result.output.contains("path-prefix=\(fixture.home.path)/.local/bin"))
        #expect(result.output.contains("managed-path=present"))
        #expect(result.output.contains("nested-path-prefix=/project/bin"))
    }

    @Test("Terminal profile loads normal user shell files and keeps Magent behavior")
    func terminalProfileLoadsUserConfiguration() throws {
        let fixture = try ShellFixture()
        defer { fixture.remove() }
        let result = try fixture.run(profile: nil)

        #expect(result.status == 0)
        #expect(result.output.contains("user-files=zshenv,zprofile,zshrc,zlogin"))
        #expect(result.output.contains("start-agent=function"))
        #expect(result.output.contains("cwd=\(fixture.worktree.path)"))
    }

    @Test("Terminal profile restores the user ZDOTDIR without a user zshrc")
    func terminalProfileWithoutZshrcRestoresUserZdotdir() throws {
        let fixture = try ShellFixture()
        defer { fixture.remove() }
        try FileManager.default.removeItem(at: fixture.home.appendingPathComponent(".zshrc"))

        let result = try fixture.run(profile: nil)

        #expect(result.status == 0)
        #expect(result.output.contains("zdotdir=\(fixture.home.path)"))
        #expect(result.output.contains("start-agent=function"))
    }
}

private struct ShellFixture {
    let root: URL
    let home: URL
    let managedZdotdir: URL
    let worktree: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("magent-shell-startup-\(UUID().uuidString)", isDirectory: true)
        home = root.appendingPathComponent("home", isDirectory: true)
        managedZdotdir = root.appendingPathComponent("managed", isDirectory: true)
        worktree = root.appendingPathComponent("worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: managedZdotdir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktree, withIntermediateDirectories: true)

        for fileName in ManagedShellStartup.managedFiles {
            try ManagedShellStartup.contents(for: fileName).write(
                to: managedZdotdir.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }
        for fileName in [".zshenv", ".zprofile", ".zshrc", ".zlogin"] {
            let label = String(fileName.dropFirst())
            try "MAGENT_TEST_USER_FILES+=(\(label))\n".write(
                to: home.appendingPathComponent(fileName),
                atomically: true,
                encoding: .utf8
            )
        }
    }

    func run(profile: String?) throws -> (status: Int32, output: String) {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-ilc",
            "print user-files=${(j:,:)MAGENT_TEST_USER_FILES:-none}; print start-agent=$(whence -w start-agent | cut -d: -f2 | tr -d ' '); print cwd=$PWD; print zdotdir=$ZDOTDIR; print path-prefix=${path[1]}; [[ $PATH == */managed/bin* ]] && print managed-path=present; PATH=/project/bin:$PATH /bin/zsh -c 'print nested-path-prefix=${path[1]}'",
        ]
        var environment = [
            "HOME": home.path,
            "MAGENT_START_CWD": worktree.path,
            "PATH": "/managed/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "ZDOTDIR": managedZdotdir.path,
        ]
        if let profile {
            environment[ManagedShellStartup.profileVariable] = profile
        }
        process.environment = environment
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
