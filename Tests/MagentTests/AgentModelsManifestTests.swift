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
