import MagentModels

public struct AgentContinuationTargets: Sendable, Equatable {
    public let agents: [AgentType]
    public let defaultAgentType: AgentType?

    public init(agents: [AgentType], defaultAgentType: AgentType?) {
        self.agents = agents
        self.defaultAgentType = defaultAgentType
    }
}

public enum AgentContinuationTargetResolver {
    public static func resolve(
        availableAgents: [AgentType],
        preferredAgent: AgentType?
    ) -> AgentContinuationTargets {
        var seen = Set<AgentType>()
        var agents = availableAgents.filter { seen.insert($0).inserted }

        if let preferredAgent, let index = agents.firstIndex(of: preferredAgent) {
            agents.remove(at: index)
            agents.insert(preferredAgent, at: 0)
        }

        return AgentContinuationTargets(
            agents: agents,
            defaultAgentType: agents.first
        )
    }
}

public enum AgentContinuationDestinationResolver {
    public static func resolve(
        agentType: AgentType,
        selectedSurface: AgentSurface?,
        chatsEnabled: Bool
    ) -> AgentSurface? {
        let surface = selectedSurface ?? agentType.defaultSurface
        return agentType.supportedSurfaces(chatsEnabled: chatsEnabled).contains(surface) ? surface : nil
    }
}
