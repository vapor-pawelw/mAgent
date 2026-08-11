import MagentCore
import Testing

@Suite("Agent continuation targets")
struct AgentContinuationTargetResolverTests {
    @Test("A chat can continue with its current provider and prefers the configured default")
    func retainsCurrentProvider() {
        let targets = AgentContinuationTargetResolver.resolve(
            availableAgents: [.claude, .codex],
            preferredAgent: .codex
        )

        #expect(targets.agents == [.codex, .claude])
        #expect(targets.defaultAgentType == .codex)
    }

    @Test("Falls back to the first enabled agent when the preference is unavailable")
    func unavailablePreference() {
        let targets = AgentContinuationTargetResolver.resolve(
            availableAgents: [.claude, .custom],
            preferredAgent: .codex
        )

        #expect(targets.agents == [.claude, .custom])
        #expect(targets.defaultAgentType == .claude)
    }

    @Test("Continue In preserves the selected terminal or chat surface")
    func preservesSelectedSurface() {
        #expect(AgentContinuationDestinationResolver.resolve(
            agentType: .codex,
            selectedSurface: .terminal,
            chatsEnabled: true
        ) == .terminal)
        #expect(AgentContinuationDestinationResolver.resolve(
            agentType: .codex,
            selectedSurface: .chat,
            chatsEnabled: true
        ) == .chat)
        #expect(AgentContinuationDestinationResolver.resolve(
            agentType: .claude,
            selectedSurface: .chat,
            chatsEnabled: true
        ) == nil)
    }
}
