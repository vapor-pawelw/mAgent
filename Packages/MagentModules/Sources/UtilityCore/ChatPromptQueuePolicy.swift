public enum ChatPromptQueueCancellationBehavior: Sendable, Equatable {
    case continueWithNextPrompt
    case discardQueuedPrompts
}

public struct ChatPromptQueueCancellationTransition<Element> {
    public let nextPrompt: Element?
    public let remainingPrompts: [Element]

    public init(nextPrompt: Element?, remainingPrompts: [Element]) {
        self.nextPrompt = nextPrompt
        self.remainingPrompts = remainingPrompts
    }
}

public enum ChatPromptQueuePolicy {
    public static func transitionAfterCancellation<Element>(
        queuedPrompts: [Element],
        behavior: ChatPromptQueueCancellationBehavior
    ) -> ChatPromptQueueCancellationTransition<Element> {
        switch behavior {
        case .continueWithNextPrompt:
            guard let nextPrompt = queuedPrompts.first else {
                return ChatPromptQueueCancellationTransition(
                    nextPrompt: nil,
                    remainingPrompts: []
                )
            }
            return ChatPromptQueueCancellationTransition(
                nextPrompt: nextPrompt,
                remainingPrompts: Array(queuedPrompts.dropFirst())
            )
        case .discardQueuedPrompts:
            return ChatPromptQueueCancellationTransition(
                nextPrompt: nil,
                remainingPrompts: []
            )
        }
    }
}
