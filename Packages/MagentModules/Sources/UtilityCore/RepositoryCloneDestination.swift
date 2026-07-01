import Foundation

public enum RepositoryCloneDestination {
    public static func suggestedDirectoryName(from remoteURL: String) -> String? {
        let trimmed = remoteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withoutFragment = trimmed
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? trimmed
        let withoutQuery = withoutFragment
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? withoutFragment
        let normalized = withoutQuery.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        let path: String
        if let url = URL(string: normalized), url.host != nil {
            path = url.path
        } else if let colonIndex = normalized.lastIndex(of: ":"),
                  !normalized[..<colonIndex].contains("/") {
            path = String(normalized[normalized.index(after: colonIndex)...])
        } else {
            path = normalized
        }

        guard var name = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty else {
            return nil
        }

        if name.hasSuffix(".git") {
            name.removeLast(4)
        }

        let invalidCharacters = CharacterSet(charactersIn: "/:")
            .union(.newlines)
            .union(.controlCharacters)
        name = name
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        return name
    }
}
