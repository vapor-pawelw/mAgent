import Foundation

/// Decoded from agent-models.json — defines available models and reasoning levels per agent.
public struct AgentModelsManifest: Codable, Sendable, Equatable {
    public let version: Int
    public let agents: [String: AgentModelConfig]

    public init(version: Int, agents: [String: AgentModelConfig]) {
        self.version = version
        self.agents = agents
    }

    /// Returns the config for a given agent type, or nil if not defined.
    public func config(for agentType: AgentType) -> AgentModelConfig? {
        agents[agentType.rawValue]
    }
}

public struct AgentModelConfig: Codable, Sendable, Equatable {
    public let models: [AgentModel]
    public let reasoningLevels: [String]

    public init(models: [AgentModel], reasoningLevels: [String]) {
        self.models = models
        self.reasoningLevels = reasoningLevels
    }

    /// Returns effective reasoning levels for a given model — the model's own override if present,
    /// otherwise the agent-level defaults.
    public func effectiveReasoningLevels(for modelId: String?) -> [String] {
        guard let modelId,
              let model = models.first(where: { $0.id == modelId }),
              let override = model.reasoningLevels else {
            return reasoningLevels
        }
        return override
    }
}

public struct AgentModel: Codable, Sendable, Equatable {
    public let id: String
    public let label: String
    public let reasoningLevels: [String]?

    public init(id: String, label: String, reasoningLevels: [String]? = nil) {
        self.id = id
        self.label = label
        self.reasoningLevels = reasoningLevels
    }
}

public enum AgentReasoningLevelPresentation {
    public static func storageValue(_ level: String?, for agentType: AgentType) -> String? {
        guard let level else { return nil }
        let normalized = level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }

        if agentType == .codex, normalized == "fast" {
            return "none"
        }
        return normalized
    }

    public static func pickerTitle(for level: String, agentType: AgentType) -> String {
        let normalized = storageValue(level, for: agentType) ?? level
        if agentType == .codex, normalized == "none" {
            return "⚡ Fast"
        }
        return normalized.capitalized
    }

    public static func verboseTitle(for level: String, agentType: AgentType) -> String {
        let normalized = storageValue(level, for: agentType) ?? level
        if agentType == .codex, normalized == "none" {
            return "fast"
        }
        return normalized.lowercased()
    }

    public static func compactTitle(for level: String?, agentType: AgentType?) -> String? {
        let trimmed = level?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "none", "fast":
            return agentType == .codex ? "⚡" : trimmed
        case "low":
            return "L"
        case "medium":
            return "M"
        case "high":
            return "H"
        case "xhigh":
            return "xH"
        case "max":
            return "Max"
        default:
            return trimmed
        }
    }
}
