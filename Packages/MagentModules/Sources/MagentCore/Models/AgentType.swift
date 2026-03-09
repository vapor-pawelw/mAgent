import Foundation

public nonisolated enum AgentType: String, Codable, CaseIterable, Sendable {
    case claude = "claude"
    case codex = "codex"
    case custom = "custom"

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        case .custom: return "Custom"
        }
    }

    /// Whether this agent type supports the /resume command for restoring conversations.
    public var supportsResume: Bool {
        self == .claude || self == .codex
    }
}
