import Foundation

public enum CodexConfigMigration {
    private static let magentHooksStartMarker = "# magent-managed-codex-hooks-start"
    private static let magentHooksEndMarker = "# magent-managed-codex-hooks-end"

    public static func preparingManagedConfig(from content: String) -> String {
        let migrated = migratingDeprecatedHooksFeatureKey(in: content)
        return removingManagedHooksBlock(from: migrated)
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

}

public enum CodexPaneActivity {
    public static func isBusy(in paneContent: String, maxLines: Int = 25) -> Bool {
        let lines = paneContent
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { strippingANSIEscapes(from: String($0)) }
        let separatorIndex = lines.lastIndex { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed.count >= 20 && trimmed.allSatisfy { $0 == "─" }
        }
        let scopedStart = separatorIndex.map { lines.index(after: $0) } ?? lines.startIndex
        let recentLines = lines[scopedStart...]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .suffix(maxLines)

        // Codex keeps the composer below MCP startup progress, so the lower prompt
        // does not mean the session is idle while that interruptible row is visible.
        if recentLines.suffix(8).contains(where: { line in
            let normalized = line.lowercased()
            return normalized.hasPrefix("• starting mcp server")
                && normalized.contains("esc to interrupt")
        }) {
            return true
        }

        for line in recentLines.reversed() {
            if line.hasPrefix("\u{203A}") {
                return false
            }
            if isBusyStatusLine(line) {
                return true
            }
        }
        return false
    }

    public static func isBusyStatusLine(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if normalized.contains("• esc to interrupt)") { return true }
        if normalized.contains("working (") && normalized.contains("esc to interrupt") { return true }
        if normalized.contains("working (") && normalized.contains("background terminal running") { return true }
        if normalized.contains("background terminal running") { return true }
        return false
    }

    private static func strippingANSIEscapes(from string: String) -> String {
        string.replacingOccurrences(
            of: #"\x1b\[[0-9;]*[a-zA-Z]"#,
            with: "",
            options: .regularExpression
        )
    }
}

public struct CodexInitialPromptReadinessGate {
    public static let defaultMinimumStableDuration: TimeInterval = 1.0

    public let minimumStableDuration: TimeInterval
    private var readySince: Date?
    private var consecutiveUnreadyObservations = 0

    public init(minimumStableDuration: TimeInterval = Self.defaultMinimumStableDuration) {
        self.minimumStableDuration = minimumStableDuration
    }

    public mutating func observe(
        at date: Date,
        composerReady: Bool,
        paneIsBusy: Bool
    ) -> Bool {
        guard composerReady, !paneIsBusy else {
            consecutiveUnreadyObservations += 1
            if consecutiveUnreadyObservations >= 2 {
                readySince = nil
            }
            return false
        }

        consecutiveUnreadyObservations = 0
        guard let readySince else {
            self.readySince = date
            return minimumStableDuration <= 0
        }
        return date.timeIntervalSince(readySince) >= minimumStableDuration
    }
}
