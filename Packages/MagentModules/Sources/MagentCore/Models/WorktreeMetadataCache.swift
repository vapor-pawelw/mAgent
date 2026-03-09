import Foundation

public struct WorktreeMetadata: Codable {
    public var forkPointCommit: String?
    public var createdAt: Date?

    public init(forkPointCommit: String? = nil, createdAt: Date? = nil) {
        self.forkPointCommit = forkPointCommit
        self.createdAt = createdAt
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
