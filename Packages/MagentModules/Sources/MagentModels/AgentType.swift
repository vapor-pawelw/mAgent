import Foundation

public nonisolated enum AgentSurface: String, Codable, CaseIterable, Sendable {
    case terminal = "terminal"
    case chat = "chat"

    public var displayName: String {
        switch self {
        case .terminal: return "Terminal"
        case .chat: return "Chat"
        }
    }
}

/// Capability matrix for a runtime agent integration.
///
/// Keep this as the single source of truth when gating UI affordances and
/// runtime behaviors (resume/model picker/rate-limit handling/etc.).
public nonisolated struct AgentCapabilityMatrix: Sendable, Equatable {
    public let supportedSurfaces: Set<AgentSurface>
    public let defaultSurface: AgentSurface
    public let supportsResume: Bool
    public let supportsModelSelection: Bool
    public let supportsReasoningSelection: Bool
    public let supportsInitialPromptInjection: Bool
    public let supportsIPCSystemPromptInjection: Bool
    public let supportsDirectoryTrustBootstrap: Bool
    public let supportsOutputRateLimitDetection: Bool
    public let supportsStructuredRateLimitSignals: Bool

    public init(
        supportedSurfaces: Set<AgentSurface>,
        defaultSurface: AgentSurface,
        supportsResume: Bool,
        supportsModelSelection: Bool,
        supportsReasoningSelection: Bool,
        supportsInitialPromptInjection: Bool,
        supportsIPCSystemPromptInjection: Bool,
        supportsDirectoryTrustBootstrap: Bool,
        supportsOutputRateLimitDetection: Bool,
        supportsStructuredRateLimitSignals: Bool
    ) {
        self.supportedSurfaces = supportedSurfaces
        self.defaultSurface = defaultSurface
        self.supportsResume = supportsResume
        self.supportsModelSelection = supportsModelSelection
        self.supportsReasoningSelection = supportsReasoningSelection
        self.supportsInitialPromptInjection = supportsInitialPromptInjection
        self.supportsIPCSystemPromptInjection = supportsIPCSystemPromptInjection
        self.supportsDirectoryTrustBootstrap = supportsDirectoryTrustBootstrap
        self.supportsOutputRateLimitDetection = supportsOutputRateLimitDetection
        self.supportsStructuredRateLimitSignals = supportsStructuredRateLimitSignals
    }
}

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
        capabilities.supportsResume
    }

    /// Capabilities supported by this agent integration in Magent.
    ///
    /// Claude and Codex are the primary tier. Other integrations may be
    /// intentionally partial (for example: no structured rate-limit signals).
    public var capabilities: AgentCapabilityMatrix {
        switch self {
        case .claude:
            return AgentCapabilityMatrix(
                supportedSurfaces: [.terminal, .chat],
                defaultSurface: .terminal,
                supportsResume: true,
                supportsModelSelection: true,
                supportsReasoningSelection: true,
                supportsInitialPromptInjection: true,
                supportsIPCSystemPromptInjection: true,
                supportsDirectoryTrustBootstrap: true,
                supportsOutputRateLimitDetection: true,
                supportsStructuredRateLimitSignals: false
            )
        case .codex:
            return AgentCapabilityMatrix(
                supportedSurfaces: [.terminal, .chat],
                defaultSurface: .terminal,
                supportsResume: true,
                supportsModelSelection: true,
                supportsReasoningSelection: true,
                supportsInitialPromptInjection: true,
                supportsIPCSystemPromptInjection: true,
                supportsDirectoryTrustBootstrap: true,
                supportsOutputRateLimitDetection: true,
                supportsStructuredRateLimitSignals: false
            )
        case .custom:
            return AgentCapabilityMatrix(
                supportedSurfaces: [.terminal],
                defaultSurface: .terminal,
                supportsResume: false,
                supportsModelSelection: false,
                supportsReasoningSelection: false,
                supportsInitialPromptInjection: true,
                supportsIPCSystemPromptInjection: false,
                supportsDirectoryTrustBootstrap: false,
                supportsOutputRateLimitDetection: false,
                supportsStructuredRateLimitSignals: false
            )
        }
    }

    /// Surfaces currently supported by this agent in the app.
    /// Keep this list conservative: only include implementations that are
    /// fully wired end-to-end in creation, restore, and runtime flows.
    public var supportedSurfaces: [AgentSurface] {
        AgentSurface.allCases.filter { capabilities.supportedSurfaces.contains($0) }
    }

    public func supportedSurfaces(chatsEnabled: Bool) -> [AgentSurface] {
        supportedSurfaces.filter { chatsEnabled || $0 == .terminal }
    }

    public var defaultSurface: AgentSurface {
        capabilities.defaultSurface
    }

    public func supports(_ surface: AgentSurface) -> Bool {
        supportedSurfaces.contains(surface)
    }

    public func displayName(for surface: AgentSurface) -> String {
        let suffixNeeded = supportedSurfaces.count > 1
        if suffixNeeded {
            return "\(displayName) (\(surface.displayName))"
        }
        return displayName
    }

    public func displayName(for surface: AgentSurface, chatsEnabled: Bool) -> String {
        let suffixNeeded = supportedSurfaces(chatsEnabled: chatsEnabled).count > 1
        if suffixNeeded {
            return "\(displayName) (\(surface.displayName))"
        }
        return displayName
    }
}
