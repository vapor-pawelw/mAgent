import Foundation

public struct WorktreeMetadata: Codable {
    public var forkPointCommit: String?
    public var createdAt: Date?
    /// Manual base branch override (e.g. "origin/develop"), set via context menu, CLI, or PR target.
    /// Also written when the original base branch is missing and gets reset to project default.
    public var detectedBaseBranch: String?
    /// Legacy field — no longer written or consumed. Retained for Codable backward compatibility.
    public var detectedFor: String?
    /// Non-nil when the base branch was auto-reset because the original no longer existed.
    /// Stores the old base branch name so a banner can be shown to the user. Cleared on acknowledgement.
    public var baseBranchResetFrom: String?

    public init(
        forkPointCommit: String? = nil,
        createdAt: Date? = nil,
        detectedBaseBranch: String? = nil,
        detectedFor: String? = nil,
        baseBranchResetFrom: String? = nil
    ) {
        self.forkPointCommit = forkPointCommit
        self.createdAt = createdAt
        self.detectedBaseBranch = detectedBaseBranch
        self.detectedFor = detectedFor
        self.baseBranchResetFrom = baseBranchResetFrom
    }
}

public struct WorktreeMetadataCache: Codable {
    public var worktrees: [String: WorktreeMetadata]
    public var nameCounter: Int

    public init(worktrees: [String: WorktreeMetadata] = [:], nameCounter: Int = 0) {
        self.worktrees = worktrees
        self.nameCounter = nameCounter
    }
}
