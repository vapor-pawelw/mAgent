import Foundation
import MagentCore

enum RepositoryRecoveryPlanner {
    static func worktreesBasePath(
        oldProject: Project,
        newRepoPath: String
    ) -> String {
        let oldWorktreesBasePath = standardizedPath(oldProject.resolvedWorktreesBasePath())
        let oldSuggestedWorktreesBasePath = standardizedPath(
            Project.suggestedWorktreesPath(for: oldProject.repoPath)
                .replacingOccurrences(of: "$MAGENT_PROJECT_NAME", with: oldProject.name)
        )
        guard oldWorktreesBasePath == oldSuggestedWorktreesBasePath else {
            return oldProject.worktreesBasePath
        }
        return Project.suggestedWorktreesPath(for: newRepoPath)
    }

    static func remappedThreadWorktreePath(
        _ path: String,
        oldRepoPath: String,
        newRepoPath: String,
        oldWorktreesBasePath: String,
        newWorktreesBasePath: String
    ) -> String {
        let normalized = standardizedPath(path)
        let normalizedOldRepoPath = standardizedPath(oldRepoPath)
        let normalizedOldWorktreesBasePath = standardizedPath(oldWorktreesBasePath)
        let normalizedNewRepoPath = standardizedPath(newRepoPath)
        let normalizedNewWorktreesBasePath = standardizedPath(newWorktreesBasePath)

        if normalized == normalizedOldRepoPath {
            return normalizedNewRepoPath
        }
        if normalized.hasPrefix(normalizedOldWorktreesBasePath + "/") {
            return normalizedNewWorktreesBasePath + String(normalized.dropFirst(normalizedOldWorktreesBasePath.count))
        }
        return path
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
