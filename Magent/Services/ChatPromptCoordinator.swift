import Foundation
import MagentCore

@MainActor
final class ChatPromptCoordinator {
    enum Client: Equatable {
        case gui
        case ipc
    }

    enum SubmissionAction {
        case start(requestID: UUID, steerChannel: AgentChatSteerChannel?)
        case steered
        case queueLocally
        case busy
    }

    static let shared = ChatPromptCoordinator()

    private struct InFlightRequest {
        let requestID: UUID
        let client: Client
        let steerChannel: AgentChatSteerChannel?
    }

    private var requestsByKey: [String: InFlightRequest] = [:]

    static func key(threadID: UUID, chatIdentifier: String) -> String {
        "\(threadID.uuidString.lowercased())::\(chatIdentifier)"
    }

    func prepareSubmission(
        key: String,
        client: Client,
        agentType: AgentType,
        prompt: String,
        messageID: UUID,
        allowsSteering: Bool
    ) -> SubmissionAction {
        if let existing = requestsByKey[key] {
            guard existing.client == client else { return .busy }
            guard allowsSteering,
                  !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let steerChannel = existing.steerChannel else {
                return client == .gui ? .queueLocally : .busy
            }
            return steerChannel.submit(AgentChatSteerInput(id: messageID, text: prompt))
                ? .steered
                : (client == .gui ? .queueLocally : .busy)
        }

        let requestID = UUID()
        let steerChannel = agentType == .codex ? AgentChatSteerChannel() : nil
        requestsByKey[key] = InFlightRequest(
            requestID: requestID,
            client: client,
            steerChannel: steerChannel
        )
        return .start(requestID: requestID, steerChannel: steerChannel)
    }

    func finishRequest(key: String, requestID: UUID) {
        guard requestsByKey[key]?.requestID == requestID else { return }
        requestsByKey.removeValue(forKey: key)
    }
}
