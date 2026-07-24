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

    @Test("Managed config preserves user hooks and adds Magent lifecycle hooks")
    func addsMagentLifecycleHooks() {
        let input = """
        model = "gpt-5.6"

        [[hooks.Stop]]
        [[hooks.Stop.hooks]]
        type = "command"
        command = "user-stop-hook"
        """

        let managed = CodexConfigMigration.preparingManagedConfig(from: input)

        #expect(managed.contains("command = \"user-stop-hook\""))
        #expect(managed.contains("[[hooks.UserPromptSubmit]]"))
        #expect(managed.contains("@magent_codex_turn_state active"))
        #expect(managed.contains("[[hooks.Stop]]"))
        #expect(managed.contains("@magent_codex_turn_state idle"))
        #expect(managed.contains("/tmp/magent-agent-completion-events.log"))
    }

    @Test("Managed lifecycle hooks remain single when config is prepared again")
    func managedHooksAreIdempotent() {
        let once = CodexConfigMigration.preparingManagedConfig(from: "")
        let twice = CodexConfigMigration.preparingManagedConfig(from: once)

        #expect(twice.components(separatedBy: "# magent-managed-codex-hooks-start").count == 2)
        #expect(twice.components(separatedBy: "[[hooks.UserPromptSubmit]]").count == 2)
        #expect(twice.components(separatedBy: "[[hooks.Stop]]").count == 2)
    }

    @Test("Codex Stop hook idle state overrides stale pane busy text")
    func stopHookIdleStateOverridesPaneText() {
        #expect(!CodexHookBusyState.resolve(
            hookState: "idle",
            paneShowsBusy: true,
            paneShowsIdlePrompt: true
        ))
        #expect(CodexHookBusyState.resolve(
            hookState: "idle",
            paneShowsBusy: true,
            paneShowsIdlePrompt: false
        ))
        #expect(CodexHookBusyState.resolve(
            hookState: "active",
            paneShowsBusy: true,
            paneShowsIdlePrompt: true
        ))
        #expect(CodexHookBusyState.resolve(
            hookState: nil,
            paneShowsBusy: true,
            paneShowsIdlePrompt: true
        ))
        #expect(!CodexHookBusyState.resolve(
            hookState: nil,
            paneShowsBusy: false,
            paneShowsIdlePrompt: false
        ))
    }
}
