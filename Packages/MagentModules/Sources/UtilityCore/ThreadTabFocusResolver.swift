public enum ThreadTabContentKind: Sendable, Equatable {
    case terminal
    case web
    case draft
    case chat
}

public enum ThreadTabFocusTarget: Sendable, Equatable {
    case terminalSurface
    case webContent
    case draftPrompt
    case chatComposer
}

public enum ThreadTabFocusResolver {
    public static func focusTarget(for contentKind: ThreadTabContentKind) -> ThreadTabFocusTarget {
        switch contentKind {
        case .terminal:
            return .terminalSurface
        case .web:
            return .webContent
        case .draft:
            return .draftPrompt
        case .chat:
            return .chatComposer
        }
    }
}
