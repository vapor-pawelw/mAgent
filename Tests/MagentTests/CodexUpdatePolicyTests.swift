import Testing

@Suite("Codex CLI updates")
struct CodexUpdatePolicyTests {
    @Test("Parses the installed version from Codex output")
    func parsesInstalledVersion() {
        #expect(CodexCLIUpdatePolicy.version(from: "codex-cli 0.146.0\n") == "0.146.0")
        #expect(CodexCLIUpdatePolicy.version(from: "startup output\ncodex-cli 0.146.0\nlogout output\n") == "0.146.0")
    }

    @Test("Offers only a newer stable version")
    func offersOnlyNewerVersion() {
        #expect(CodexCLIUpdatePolicy.updateSummary(installedVersion: "0.146.0", availableVersion: "0.147.0", skippedVersion: nil)?.availableVersion == "0.147.0")
        #expect(CodexCLIUpdatePolicy.updateSummary(installedVersion: "0.147.0", availableVersion: "0.147.0", skippedVersion: nil) == nil)
        #expect(CodexCLIUpdatePolicy.updateSummary(installedVersion: "0.148.0", availableVersion: "0.147.0", skippedVersion: nil) == nil)
    }

    @Test("Keeps skipped updates available for Settings")
    func preservesSkippedUpdate() throws {
        let summary = try #require(CodexCLIUpdatePolicy.updateSummary(installedVersion: "0.146.0", availableVersion: "0.147.0", skippedVersion: "0.147.0"))
        #expect(summary.isSkipped)
    }
}
