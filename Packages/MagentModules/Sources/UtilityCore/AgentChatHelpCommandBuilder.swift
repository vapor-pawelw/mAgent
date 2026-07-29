import Foundation

public enum AgentChatHelpCommandBuilder {
    public static func effortUsage(reasoningLevels: [String]) -> String {
        let normalizedLevels = reasoningLevels.compactMap { level -> String? in
            let trimmed = level.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !normalizedLevels.isEmpty else { return "/effort" }
        return "/effort <\(normalizedLevels.joined(separator: "|"))>"
    }
}
