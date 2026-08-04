import Foundation

public enum ChatMessageContextAction: Equatable, Sendable {
    case copy
    case renameTabFromMessage
}

public enum ChatMessageContextActions {
    public static func availableActions(messageText: String) -> [ChatMessageContextAction] {
        let hasText = !messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasText ? [.copy, .renameTabFromMessage] : [.copy]
    }
}
