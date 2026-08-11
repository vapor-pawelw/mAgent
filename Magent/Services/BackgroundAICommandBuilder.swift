import Foundation
import MagentCore

enum BackgroundAICommandBuilder {
    static func codex(escapedPrompt: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let localBin = ShellExecutor.shellQuote("\(homeDir)/.local/bin")
        let miseShims = ShellExecutor.shellQuote("\(homeDir)/.local/share/mise/shims")
        return "PATH=\(localBin):\(miseShims):$PATH command codex exec \(escapedPrompt) --ephemeral --ignore-user-config --ignore-rules --model gpt-5.6-luna --config model_reasoning_effort=none < /dev/null"
    }

    static func claude(escapedPrompt: String) -> String {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        return "PATH=\(homeDir)/.local/bin:$PATH command claude -p \(escapedPrompt) --model haiku --no-session-persistence --tools \"\" --setting-sources \"\" < /dev/null"
    }
}
