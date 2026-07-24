import Foundation

enum AIRenameTarget: CaseIterable {
    case icon
    case description
    case branch

    static func availableTargets(allowsIconRename: Bool) -> [Self] {
        allCases.filter { allowsIconRename || $0 != .icon }
    }

    static func shouldRenameIcon(allowsIconRename: Bool, isSelected: Bool) -> Bool {
        allowsIconRename && isSelected
    }
}

enum RenameGenerationPromptBuilder {
    private static let iconInstructions = """
        Icon types: feature (new functionality), fix (bug/regression), improvement (non-breaking polish/performance/quality), refactor (internal code restructure), test (adding/updating tests), other (none fit). \
        Evaluate all icon types and use other when no icon type is above 70% confidence.
        """

    static func cacheKey(for prompt: String, includeIcon: Bool) -> String {
        let normalizedPrompt = prompt
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return "\(includeIcon ? "with-icon" : "without-icon"):\(normalizedPrompt)"
    }

    static func combinedRename(
        task: String,
        slugInstruction: String,
        includeIcon: Bool
    ) -> String {
        let descriptionInstructions = """
            Also generate a short task description (2-8 words) with first letter uppercase. \
            The description should read like a clear branch/sidebar label for the work to do, and should describe the same task as the slug. \
            Prefer concrete phrases such as "Fix ...", "Add ...", "Improve ...", or a specific feature/bug name. Avoid vague abstract wording like "readiness", "handling", "management", or "support" unless that exact concept is the task.
            """
        let outputInstructions = includeIcon
            ? """
              Output exactly three lines and nothing else: \
              SLUG: <slug> \
              DESC: <description> \
              TYPE: <feature|fix|improvement|refactor|test|other>
              """
            : """
              Output exactly two lines and nothing else: \
              SLUG: <slug> \
              DESC: <description>
              """
        let iconSection = includeIcon ? "\(iconInstructions) " : ""

        return """
            \(slugInstruction) \
            \(descriptionInstructions) \
            \(iconSection)\(outputInstructions) \
            Task: \(task)
            """
    }

    static func taskDescription(task: String, includeIcon: Bool) -> String {
        let outputInstructions = includeIcon
            ? """
              Output exactly two lines and nothing else: \
              DESC: <description> \
              TYPE: <feature|fix|improvement|refactor|test|other>
              """
            : """
              Output exactly one line and nothing else: \
              DESC: <description>
              """
        let iconSection = includeIcon
            ? "\(iconInstructions.replacingOccurrences(of: "Evaluate all icon types and use other", with: "Evaluate all icon types, pick the highest-confidence one, and use other")) "
            : ""

        return """
            Generate a short task description (2-8 words) in natural casing, with the first letter uppercase. \
            The description should read like a clear branch/sidebar label for the work to do. \
            Prefer concrete phrases such as "Fix ...", "Add ...", "Improve ...", or a specific feature/bug name. Avoid vague abstract wording like "readiness", "handling", "management", or "support" unless that exact concept is the task. \
            \(iconSection)\(outputInstructions) \
            Task: \(task)
            """
    }
}
