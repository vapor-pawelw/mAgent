import Foundation
import Testing
import MagentCore

@Suite("Agent model manifest")
struct AgentModelsManifestTests {
    @Test("Bundled manifest lists Claude Fable above Opus")
    func bundledManifestListsClaudeFableAboveOpus() throws {
        let manifest = try loadRepositoryManifest()
        let claudeModels = try #require(manifest.config(for: .claude)?.models)

        #expect(claudeModels.contains(AgentModel(id: "fable", label: "Fable")))
        let fableIndex = try #require(claudeModels.firstIndex { $0.id == "fable" })
        let opusIndex = try #require(claudeModels.firstIndex { $0.id == "opus" })
        #expect(fableIndex < opusIndex)
    }

    @Test("Bundled manifest exposes Ultra only for supported GPT 5.6 models")
    func bundledManifestExposesUltraForSupportedGPT56Models() throws {
        let manifest = try loadRepositoryManifest()
        let codexConfig = try #require(manifest.config(for: .codex))

        #expect(codexConfig.models.first?.id == "gpt-5.6-sol")
        #expect(codexConfig.effectiveReasoningLevels(for: "gpt-5.6-sol").contains("ultra"))
        #expect(codexConfig.effectiveReasoningLevels(for: "gpt-5.6-terra").contains("ultra"))
        #expect(!codexConfig.effectiveReasoningLevels(for: "gpt-5.6-luna").contains("ultra"))
    }

    @Test("Bundled manifest exposes Codex fast reasoning")
    func bundledManifestExposesCodexFastReasoning() throws {
        let manifest = try loadRepositoryManifest()
        let codexConfig = try #require(manifest.config(for: .codex))

        #expect(codexConfig.reasoningLevels.first == "none")
        #expect(AgentReasoningLevelPresentation.storageValue("fast", for: .codex) == "none")
        #expect(AgentReasoningLevelPresentation.pickerTitle(for: "none", agentType: .codex) == "⚡ Fast")
        #expect(AgentReasoningLevelPresentation.verboseTitle(for: "none", agentType: .codex) == "fast")
    }

    private func loadRepositoryManifest() throws -> AgentModelsManifest {
        let testFile = URL(fileURLWithPath: #filePath)
        let repoRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let manifestURL = repoRoot
            .appendingPathComponent("config")
            .appendingPathComponent("agent-models.json")
        let data = try Data(contentsOf: manifestURL)
        return try JSONDecoder().decode(AgentModelsManifest.self, from: data)
    }
}
