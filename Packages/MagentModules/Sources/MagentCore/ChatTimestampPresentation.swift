import Foundation

public enum ChatTimestampDisplayMode: Sendable, Equatable {
    case relative
    case exact

    public mutating func toggle() {
        switch self {
        case .relative:
            self = .exact
        case .exact:
            self = .relative
        }
    }
}

public enum ChatTimestampPresentation {
    public static func displayText(
        mode: ChatTimestampDisplayMode,
        relativeText: String,
        exactText: String,
        hoverText: String?
    ) -> String {
        switch mode {
        case .exact:
            return exactText
        case .relative:
            if let hoverText, !hoverText.isEmpty {
                return hoverText
            }
            return relativeText
        }
    }
}
