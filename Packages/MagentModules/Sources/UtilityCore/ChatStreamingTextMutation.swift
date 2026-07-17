import Foundation

public enum ChatStreamingTextMutation: Equatable, Sendable {
    case noChange
    case replace
    case appendStyledTail(replaceFromUTF16Offset: Int, replacementText: String)
    case appendUsingPreviousAttributes(delta: String)
}

public enum ChatStreamingTextMutationPlanner {
    public static func plan(
        previous: String,
        next: String,
        maximumRestyledCharacterCount: Int = 256
    ) -> ChatStreamingTextMutation {
        guard previous != next else { return .noChange }
        guard next.hasPrefix(previous) else { return .replace }

        let delta = String(next.dropFirst(previous.count))
        if hasUnclosedCodeFence(previous) {
            return .appendUsingPreviousAttributes(delta: delta)
        }

        let lookbehind = max(0, maximumRestyledCharacterCount)
        let lowerBound = previous.index(previous.endIndex, offsetBy: -min(lookbehind, previous.count))
        let recentText = previous[lowerBound...]
        let paragraphStart: String.Index
        if let boundary = recentText.range(of: "\n\n", options: .backwards)?.upperBound {
            paragraphStart = boundary
        } else {
            paragraphStart = lowerBound
        }

        let utf16Offset = previous[..<paragraphStart].utf16.count
        return .appendStyledTail(
            replaceFromUTF16Offset: utf16Offset,
            replacementText: String(next[paragraphStart...])
        )
    }

    private static func hasUnclosedCodeFence(_ text: String) -> Bool {
        text.components(separatedBy: "```").count.isMultiple(of: 2)
    }
}
