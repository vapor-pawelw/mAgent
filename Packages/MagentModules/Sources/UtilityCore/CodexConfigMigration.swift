import Foundation

public enum CodexConfigMigration {
    private static let magentHooksStartMarker = "# magent-managed-codex-hooks-start"
    private static let magentHooksEndMarker = "# magent-managed-codex-hooks-end"

    public static func preparingManagedConfig(from content: String) -> String {
        let migrated = migratingDeprecatedHooksFeatureKey(in: content)
        let withoutExistingMagentHooks = removingManagedHooksBlock(from: migrated)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = withoutExistingMagentHooks.isEmpty ? "" : "\n\n"

        return withoutExistingMagentHooks + separator + magentHooksBlock + "\n"
    }

    public static func migratingDeprecatedHooksFeatureKey(in content: String) -> String {
        let endsWithNewline = content.hasSuffix("\n")
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let featuresAlreadyContainsHooks = containsHooksKey(inFeaturesSectionOf: lines)
        var section: String?
        var sawHooksInFeatures = false
        var output: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                sawHooksInFeatures = false
                output.append(line)
                continue
            }

            guard section == "features" else {
                output.append(line)
                continue
            }

            let uncommented = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first?
                .trimmingCharacters(in: .whitespaces) ?? trimmed
            let key = uncommented.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first?
                .trimmingCharacters(in: .whitespaces)

            if key == "hooks" {
                sawHooksInFeatures = true
                output.append(line)
            } else if key == "codex_hooks" {
                if !featuresAlreadyContainsHooks && !sawHooksInFeatures {
                    output.append(line.replacingOccurrences(of: "codex_hooks", with: "hooks"))
                    sawHooksInFeatures = true
                }
            } else {
                output.append(line)
            }
        }

        let migrated = output.joined(separator: "\n")
        return endsWithNewline ? migrated + "\n" : migrated
    }

    private static func containsHooksKey(inFeaturesSectionOf lines: [String]) -> Bool {
        var section: String?
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                section = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                continue
            }

            guard section == "features" else { continue }
            if key(in: trimmed) == "hooks" {
                return true
            }
        }
        return false
    }

    private static func key(in trimmedLine: String) -> String? {
        let uncommented = trimmedLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespaces) ?? trimmedLine
        return uncommented.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).first?
            .trimmingCharacters(in: .whitespaces)
    }

    private static func removingManagedHooksBlock(from content: String) -> String {
        var isInsideManagedBlock = false
        return content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { substring -> String? in
                let line = String(substring)
                if line.trimmingCharacters(in: .whitespaces) == magentHooksStartMarker {
                    isInsideManagedBlock = true
                    return nil
                }
                if line.trimmingCharacters(in: .whitespaces) == magentHooksEndMarker {
                    isInsideManagedBlock = false
                    return nil
                }
                return isInsideManagedBlock ? nil : line
            }
            .joined(separator: "\n")
    }

    private static let magentHooksBlock = """
    \(magentHooksStartMarker)
    [[hooks.UserPromptSubmit]]

    [[hooks.UserPromptSubmit.hooks]]
    type = "command"
    command = '[ -n "$MAGENT_WORKTREE_NAME" ] && tmux set-option -pq -t "$TMUX_PANE" @magent_codex_turn_state active || true'
    timeout = 5

    [[hooks.Stop]]

    [[hooks.Stop.hooks]]
    type = "command"
    command = 'if [ -n "$MAGENT_WORKTREE_NAME" ]; then tmux set-option -pq -t "$TMUX_PANE" @magent_codex_turn_state idle; magent_session="$(tmux display-message -p -t "$TMUX_PANE" "#{session_name}")"; magent_completed_at="$(/usr/bin/perl -MTime::HiRes=time -e "print time")"; printf "%s\\t%s\\n" "$magent_session" "$magent_completed_at" >> /tmp/magent-agent-completion-events.log; fi; true'
    timeout = 5
    \(magentHooksEndMarker)
    """
}

public enum CodexHookBusyState {
    public static func resolve(
        hookState: String?,
        paneShowsBusy: Bool,
        paneShowsIdlePrompt: Bool
    ) -> Bool {
        hookState == "idle" && paneShowsIdlePrompt ? false : paneShowsBusy
    }
}
