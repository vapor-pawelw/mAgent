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
}
