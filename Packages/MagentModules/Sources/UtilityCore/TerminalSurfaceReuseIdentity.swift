import Foundation
import MagentModels

public struct TerminalSurfaceReuseIdentity: Equatable, Sendable {
    public let threadID: UUID
    public let sessionName: String
    public let worktreePath: String
    public let isAgentSession: Bool
    public let agentType: AgentType?
    public let sessionCreatedAt: Date?

    public init(
        threadID: UUID,
        sessionName: String,
        worktreePath: String,
        isAgentSession: Bool,
        agentType: AgentType?,
        sessionCreatedAt: Date?
    ) {
        self.threadID = threadID
        self.sessionName = sessionName
        self.worktreePath = URL(fileURLWithPath: worktreePath).standardizedFileURL.path
        self.isAgentSession = isAgentSession
        self.agentType = agentType
        self.sessionCreatedAt = sessionCreatedAt
    }

    public var cacheKey: String {
        [
            threadID.uuidString,
            sessionName,
            worktreePath,
            isAgentSession ? "agent" : "terminal",
            agentType?.rawValue ?? "none",
            sessionCreatedAt.map { String($0.timeIntervalSince1970) } ?? "unknown",
        ].joined(separator: "\n")
    }
}
