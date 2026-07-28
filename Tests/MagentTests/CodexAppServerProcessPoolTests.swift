import Foundation
import Testing
@testable import UtilityCore

@Suite("Codex app-server process reuse")
struct CodexAppServerProcessPoolTests {
    @Test("A completed turn leaves its live app-server available to the next turn")
    func reusesLiveHostForSameThreadAndConfiguration() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let configuration = CodexAppServerConnectionConfiguration(
            workingDirectory: "/tmp/worktree",
            developerInstructions: "Use Magent IPC",
            skipPermissions: false,
            sandboxEnabled: true
        )
        let host = CodexAppServerProcessHost(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            configuration: configuration
        )
        let pool = CodexAppServerProcessPool()

        pool.register(host, threadID: "thread-1")
        pool.release(host, keepAlive: true)

        let reused = pool.acquire(threadID: "thread-1", configuration: configuration)
        #expect(reused === host)

        pool.release(host, keepAlive: false)
        process.waitUntilExit()
    }

    @Test("Permission changes do not reuse a process launched with stale settings")
    func doesNotReuseHostWithDifferentConfiguration() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let originalConfiguration = CodexAppServerConnectionConfiguration(
            workingDirectory: "/tmp/worktree",
            developerInstructions: nil,
            skipPermissions: false,
            sandboxEnabled: true
        )
        let host = CodexAppServerProcessHost(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            configuration: originalConfiguration
        )
        let pool = CodexAppServerProcessPool()
        pool.register(host, threadID: "thread-1")
        pool.release(host, keepAlive: true)

        let changedConfiguration = CodexAppServerConnectionConfiguration(
            workingDirectory: "/tmp/worktree",
            developerInstructions: nil,
            skipPermissions: true,
            sandboxEnabled: false
        )
        #expect(pool.acquire(threadID: "thread-1", configuration: changedConfiguration) == nil)

        process.waitUntilExit()
        #expect(!process.isRunning)
    }

    @Test("A second turn waits for the active turn before leasing the same app-server")
    func serializesTurnsForSameThread() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let configuration = CodexAppServerConnectionConfiguration(
            workingDirectory: "/tmp/worktree",
            developerInstructions: nil,
            skipPermissions: false,
            sandboxEnabled: true
        )
        let host = CodexAppServerProcessHost(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            configuration: configuration
        )
        let pool = CodexAppServerProcessPool()
        pool.register(host, threadID: "thread-1")

        let acquireStarted = DispatchSemaphore(value: 0)
        let acquireFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            acquireStarted.signal()
            if let leasedHost = pool.acquire(threadID: "thread-1", configuration: configuration) {
                pool.release(leasedHost, keepAlive: false)
            }
            acquireFinished.signal()
        }

        #expect(acquireStarted.wait(timeout: .now() + 1) == .success)
        #expect(acquireFinished.wait(timeout: .now() + 0.05) == .timedOut)

        pool.release(host, keepAlive: true)

        #expect(acquireFinished.wait(timeout: .now() + 1) == .success)
        process.waitUntilExit()
    }

    @Test("A turn waiting for a busy app-server can be cancelled")
    func cancelsWhileWaitingForActiveTurn() throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cat")
        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()

        let configuration = CodexAppServerConnectionConfiguration(
            workingDirectory: "/tmp/worktree",
            developerInstructions: nil,
            skipPermissions: false,
            sandboxEnabled: true
        )
        let host = CodexAppServerProcessHost(
            process: process,
            stdinPipe: stdinPipe,
            stdoutPipe: stdoutPipe,
            stderrPipe: stderrPipe,
            configuration: configuration
        )
        let pool = CodexAppServerProcessPool()
        pool.register(host, threadID: "thread-1")

        let acquireStarted = DispatchSemaphore(value: 0)
        let cancellationRequested = DispatchSemaphore(value: 0)
        let acquireFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            acquireStarted.signal()
            let leasedHost = pool.acquire(
                threadID: "thread-1",
                configuration: configuration,
                isCancelled: {
                    cancellationRequested.wait(timeout: .now()) == .success
                }
            )
            #expect(leasedHost == nil)
            acquireFinished.signal()
        }

        #expect(acquireStarted.wait(timeout: .now() + 1) == .success)
        #expect(acquireFinished.wait(timeout: .now() + 0.05) == .timedOut)
        cancellationRequested.signal()
        #expect(acquireFinished.wait(timeout: .now() + 1) == .success)

        pool.release(host, keepAlive: false)
        process.waitUntilExit()
    }
}
