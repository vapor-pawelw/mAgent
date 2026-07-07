import Foundation

public enum CodexConfigMigration {
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
}
