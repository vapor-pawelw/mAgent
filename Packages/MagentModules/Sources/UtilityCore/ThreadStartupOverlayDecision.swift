import Foundation

public enum ThreadStartupOverlayAction: Equatable {
    case skip
    case track
}

public enum ThreadStartupOverlayDecision {
    public static func action(
        isRestoringTerminalTab: Bool,
        requiresStartupOverlay: Bool,
        canFastPathSelectedSession: Bool
    ) -> ThreadStartupOverlayAction {
        guard isRestoringTerminalTab else { return .skip }
        if canFastPathSelectedSession && !requiresStartupOverlay {
            return .skip
        }
        return .track
    }
}
