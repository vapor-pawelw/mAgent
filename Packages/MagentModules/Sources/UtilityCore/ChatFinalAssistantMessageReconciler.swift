import Foundation
import MagentModels

public enum ChatFinalAssistantMessageReconciler {
    public static func messagesByReconcilingFinalAssistantText(
        _ messages: [PersistedChatMessage],
        streamedMessageIDs: Set<UUID>,
        finalText: String,
        modelId: String?,
        reasoningLevel: String?
    ) -> (messages: [PersistedChatMessage], didMutate: Bool) {
        let normalizedFinalText = finalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedFinalText.isEmpty else {
            return (messages, false)
        }

        var updated = messages
        let streamedIndices = updated.indices.filter { streamedMessageIDs.contains(updated[$0].id) }
        guard let firstStreamedIndex = streamedIndices.first else {
            updated.append(PersistedChatMessage(
                role: .assistant,
                text: normalizedFinalText,
                modelId: modelId,
                reasoningLevel: reasoningLevel
            ))
            return (updated, true)
        }

        var didMutate = false
        let streamedText = streamedIndices
            .map { updated[$0].text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")

        if streamedText != normalizedFinalText || updated[firstStreamedIndex].text != normalizedFinalText {
            updated[firstStreamedIndex].text = normalizedFinalText
            didMutate = true
        }
        if updated[firstStreamedIndex].modelId != modelId {
            updated[firstStreamedIndex].modelId = modelId
            didMutate = true
        }
        if updated[firstStreamedIndex].reasoningLevel != reasoningLevel {
            updated[firstStreamedIndex].reasoningLevel = reasoningLevel
            didMutate = true
        }

        for index in streamedIndices.dropFirst().reversed() {
            updated.remove(at: index)
            didMutate = true
        }

        return (updated, didMutate)
    }
}
