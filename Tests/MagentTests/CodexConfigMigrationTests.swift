import Foundation
import Testing
import MagentCore

@Suite("CodexConfigMigration")
struct CodexConfigMigrationTests {
    @Test("Migrates deprecated codex_hooks key inside features section")
    func migratesDeprecatedHooksFeatureKey() {
        let input = """
        model = "gpt-5.5"

        [features]
        js_repl = false
        codex_hooks = true

        [projects."/repo"]
        trust_level = "trusted"

        """

        let migrated = CodexConfigMigration.migratingDeprecatedHooksFeatureKey(in: input)

        #expect(migrated.contains("hooks = true"))
        #expect(!migrated.contains("codex_hooks = true"))
        #expect(migrated.contains("js_repl = false"))
        #expect(migrated.hasSuffix("\n"))
    }

    @Test("Preserves existing hooks key and drops deprecated duplicate")
    func preservesExistingHooksKey() {
        let input = """
        [features]
        hooks = true
        codex_hooks = false
        js_repl = false
        """

        let migrated = CodexConfigMigration.migratingDeprecatedHooksFeatureKey(in: input)

        #expect(migrated.contains("hooks = true"))
        #expect(!migrated.contains("codex_hooks"))
        #expect(migrated.contains("js_repl = false"))
    }

    @Test("Preserves existing hooks key when deprecated key appears first")
    func preservesExistingHooksKeyWhenDeprecatedKeyAppearsFirst() {
        let input = """
        [features]
        codex_hooks = false
        hooks = true
        js_repl = false
        """

        let migrated = CodexConfigMigration.migratingDeprecatedHooksFeatureKey(in: input)

        #expect(migrated.components(separatedBy: "hooks =").count - 1 == 1)
        #expect(!migrated.contains("codex_hooks"))
        #expect(migrated.contains("hooks = true"))
    }

    @Test("Leaves similarly named keys outside features untouched")
    func leavesOtherSectionsUntouched() {
        let input = """
        [custom]
        codex_hooks = true
        """

        #expect(CodexConfigMigration.migratingDeprecatedHooksFeatureKey(in: input) == input)
    }

    @Test("Leaves similarly prefixed feature keys untouched")
    func leavesSimilarlyPrefixedFeatureKeysUntouched() {
        let input = """
        [features]
        hooks_enabled = false
        codex_hooks_enabled = true
        codex_hooks = true
        """

        let migrated = CodexConfigMigration.migratingDeprecatedHooksFeatureKey(in: input)

        #expect(migrated.contains("hooks_enabled = false"))
        #expect(migrated.contains("codex_hooks_enabled = true"))
        #expect(migrated.contains("hooks = true"))
    }

    @Test("Managed config preserves user hooks without adding Magent lifecycle hooks")
    func doesNotAddMagentLifecycleHooks() {
        let input = """
        model = "gpt-5.6"

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "user-stop-hook"
        """

        let managed = CodexConfigMigration.preparingManagedConfig(from: input)

        #expect(managed.contains("command = \"user-stop-hook\""))
        #expect(!managed.contains("[[hooks.UserPromptSubmit]]"))
        #expect(!managed.contains("@magent_codex_turn_state"))
    }

    @Test("Managed config removes lifecycle hooks injected by older Magent builds")
    func removesPreviouslyManagedHooks() {
        let input = """
        model = "gpt-5.6"

        # magent-managed-codex-hooks-start
        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "magent-stop-hook"
        # magent-managed-codex-hooks-end
        """

        let managed = CodexConfigMigration.preparingManagedConfig(from: input)

        #expect(managed.contains("model = \"gpt-5.6\""))
        #expect(!managed.contains("magent-managed-codex-hooks"))
        #expect(!managed.contains("magent-stop-hook"))
    }

    @Test("A newer Codex idle prompt clears stale busy output")
    func newerIdlePromptWins() {
        let pane = """
        › Run the tests
        Working (2m 12s • esc to interrupt)
        Finished successfully
        ›
        """

        #expect(!CodexPaneActivity.isBusy(in: pane))
    }

    @Test("A newer Codex activity footer keeps the session busy")
    func newerBusyStatusWins() {
        let pane = """
        Working (2m 12s • esc to interrupt)
        › Run the tests
        Working (3s • esc to interrupt) · 1 background terminal running
        """

        #expect(CodexPaneActivity.isBusy(in: pane))
    }

    @Test("Codex remains busy when its composer stays below the Working row")
    func workingStatusAboveComposerWins() {
        let pane = """
        • Ran build command
        Working (35m 47s • esc to interrupt)
        ╭──────────────────────────────╮
        › Explain this codebase
        """

        #expect(CodexPaneActivity.isBusy(in: pane))
    }

    @Test("Completed output between Working and the composer remains idle")
    func completedOutputAboveComposerWins() {
        let pane = """
        Working (35m 47s • esc to interrupt)
        Finished successfully

        › Explain this codebase
        """

        #expect(!CodexPaneActivity.isBusy(in: pane))
    }

    @Test("Codex MCP startup remains busy while its composer is visible")
    func mcpStartupOverridesComposerPrompt() {
        let pane = """
        • Starting MCP servers (4/5): xcodebuildmcp (23s • esc to interrupt)

        › Explain this codebase
        """

        #expect(CodexPaneActivity.isBusy(in: pane))
    }

    @Test("Separate stale MCP and interrupt text does not override an idle prompt")
    func unrelatedMCPTextDoesNotOverrideIdlePrompt() {
        let pane = """
        • Starting MCP servers failed earlier
        Working (2m 12s • esc to interrupt)
        Finished successfully
        ›
        """

        #expect(!CodexPaneActivity.isBusy(in: pane))
    }

    @Test("Older exact MCP startup rows do not latch busy state")
    func olderMCPStartupDoesNotOverrideIdlePrompt() {
        let pane = """
        • Starting MCP servers (4/5): xcodebuildmcp (23s • esc to interrupt)
        Startup result
        Turn output 1
        Turn output 2
        Turn output 3
        Turn output 4
        Turn output 5
        Turn output 6
        Turn output 7
        ›
        """

        #expect(!CodexPaneActivity.isBusy(in: pane))
    }

    @Test("Older Codex pane scopes cannot latch busy state")
    func olderPaneScopeIsIgnored() {
        let pane = """
        › Run the tests
        Working (2m 12s • esc to interrupt)
        ──────────────────────────────
        Finished successfully
        """

        #expect(!CodexPaneActivity.isBusy(in: pane))
    }
}
