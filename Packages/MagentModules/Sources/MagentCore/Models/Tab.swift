import Foundation

public nonisolated struct Tab: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let threadId: UUID
    public var tmuxSessionName: String
    public var index: Int

    public init(
        id: UUID = UUID(),
        threadId: UUID,
        tmuxSessionName: String,
        index: Int
    ) {
        self.id = id
        self.threadId = threadId
        self.tmuxSessionName = tmuxSessionName
        self.index = index
    }
}
