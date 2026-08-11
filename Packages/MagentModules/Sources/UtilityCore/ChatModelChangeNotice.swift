import Foundation
import MagentModels

public enum ChatModelChangeNotice {
    public static func noticeText(modelName: String?, reasoningLevel: String?) -> String {
        let model = normalizedDisplay(modelName) ?? "Default model"
        let reasoning = normalizedDisplay(reasoningLevel) ?? "default"
        return "Model changed to \(model) (\(reasoning))"
    }

    public static func messagesByInjectingNoticeIfNeeded(
        into messages: [PersistedChatMessage],
        nextModelName: String?,
        nextModelId: String?,
        nextReasoningLevel: String?,
        createdAt: Date = Date()
    ) -> [PersistedChatMessage] {
        guard let previousUser = messages.reversed().first(where: { $0.role == .user }) else {
            return messages
        }
        guard normalizedIdentity(previousUser.modelId) != normalizedIdentity(nextModelId)
            || normalizedIdentity(previousUser.reasoningLevel) != normalizedIdentity(nextReasoningLevel) else {
            return messages
        }

        var updated = messages
        updated.append(
            PersistedChatMessage(
                role: .system,
                text: noticeText(modelName: nextModelName ?? nextModelId, reasoningLevel: nextReasoningLevel),
                createdAt: createdAt,
                modelId: nextModelId,
                reasoningLevel: nextReasoningLevel,
                origin: .localUI
            )
        )
        return updated
    }

    private static func normalizedIdentity(_ value: String?) -> String? {
        guard let trimmed = normalizedDisplay(value) else { return nil }
        return trimmed.lowercased()
    }

    private static func normalizedDisplay(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }
}

public enum ChatModelSelectionSynchronization {
    public static func shouldNotifyParent(
        previousModelId: String?,
        previousReasoningLevel: String?,
        resolvedModelId: String?,
        resolvedReasoningLevel: String?
    ) -> Bool {
        previousModelId != resolvedModelId || previousReasoningLevel != resolvedReasoningLevel
    }
}
