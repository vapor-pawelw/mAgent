import Foundation
import Testing
import MagentCore

@Suite("IPCAgentDocs Codex AGENTS merge")
struct IPCAgentDocsTests {

    @Test("include=false removes Magent block and preserves user text")
    func stripsMagentBlockWhenDisabled() {
        let user = """
        # User Notes

        Keep this.

        \(IPCAgentDocs.codexAgentsMdBlock)
        """

        let merged = IPCAgentDocs.codexMergedAgentsMd(
            userContent: user,
            includeMagentIPC: false
        )

        #expect(merged.contains("# User Notes"))
        #expect(merged.contains("Keep this."))
        #expect(!merged.contains(IPCAgentDocs.codexIPCMarkerStart))
    }

    @Test("include=true appends Magent block to user content")
    func appendsMagentBlockWhenEnabled() {
        let merged = IPCAgentDocs.codexMergedAgentsMd(
            userContent: "# User Notes\nKeep this.",
            includeMagentIPC: true
        )

        #expect(merged.contains("# User Notes"))
        #expect(merged.contains("Keep this."))
        #expect(merged.contains(IPCAgentDocs.codexIPCMarkerStart))
        #expect(merged.contains(IPCAgentDocs.codexIPCVersion))
    }

    @Test("include=true with nil user content returns Magent block only")
    func magentOnlyWhenNoUserContent() {
        let merged = IPCAgentDocs.codexMergedAgentsMd(
            userContent: nil,
            includeMagentIPC: true
        )
        #expect(merged == IPCAgentDocs.codexAgentsMdBlock)
    }

    @Test("include=true does not duplicate existing Magent block")
    func noDuplicateMagentBlock() {
        let user = """
        # User Notes

        \(IPCAgentDocs.codexAgentsMdBlock)
        """

        let merged = IPCAgentDocs.codexMergedAgentsMd(
            userContent: user,
            includeMagentIPC: true
        )

        let occurrences = merged.components(separatedBy: IPCAgentDocs.codexIPCMarkerStart).count - 1
        #expect(occurrences == 1)
    }

    @Test("Codex developer instructions include Magent IPC guidance")
    func codexDeveloperInstructionsGuidance() {
        #expect(IPCAgentDocs.codexDeveloperInstructions.contains("/tmp/magent-cli"))
        #expect(IPCAgentDocs.codexDeveloperInstructions.contains("/tmp/magent-cli docs"))
        #expect(IPCAgentDocs.codexDeveloperInstructions.contains("thread"))
        #expect(IPCAgentDocs.codexDeveloperInstructions.contains("tab"))
    }

    @Test("CLI reference documents start-agent")
    func cliReferenceDocumentsStartAgent() {
        #expect(IPCAgentDocs.cliReferenceText.contains("/tmp/magent-cli start-agent"))
        #expect(IPCAgentDocs.cliReferenceText.contains("launch or resume"))
    }

    @Test("IPC response can carry shell command")
    func ipcResponseEncodesShellCommand() throws {
        let response = IPCResponse(ok: true, shellCommand: "start-agent")
        let data = try JSONEncoder().encode(response)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["ok"] as? Bool == true)
        #expect(object["shellCommand"] as? String == "start-agent")
    }
}
