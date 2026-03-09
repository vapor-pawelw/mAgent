import Foundation

public nonisolated struct DependencyStatus: Sendable {
    public let name: String
    public let isInstalled: Bool
    public let path: String?
    public let installHint: String
}

public final class DependencyChecker: Sendable {

    public static let shared = DependencyChecker()

    public func checkAll() async -> [DependencyStatus] {
        async let tmux = checkTmux()
        async let git = checkGit()
        return await [git, tmux]
    }

    public func checkGit() async -> DependencyStatus {
        let path = await findExecutable("git")
        return DependencyStatus(
            name: "git",
            isInstalled: path != nil,
            path: path,
            installHint: "Install Xcode Command Line Tools: xcode-select --install"
        )
    }

    public func checkTmux() async -> DependencyStatus {
        let path = await findExecutable("tmux")
        return DependencyStatus(
            name: "tmux",
            isInstalled: path != nil,
            path: path,
            installHint: "Install via Homebrew: brew install tmux"
        )
    }

    public func allDependenciesMet() async -> Bool {
        let statuses = await checkAll()
        return statuses.allSatisfy(\.isInstalled)
    }

    private func findExecutable(_ name: String) async -> String? {
        let result = await ShellExecutor.execute("which \(name)")
        if result.exitCode == 0 {
            let path = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : path
        }
        return nil
    }
}
