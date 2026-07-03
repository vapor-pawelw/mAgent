import Foundation
import Testing
import MagentCore

@Suite("Agent model manifest")
struct AgentModelsManifestTests {
    @Test("Bundled manifest exposes Claude Fable")
    func bundledManifestExposesClaudeFable() throws {
        let manifest = try loadRepositoryManifest()
        let claudeModels = try #require(manifest.config(for: .claude)?.models)

        #expect(claudeModels.contains(AgentModel(id: "fable", label: "Fable")))
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
