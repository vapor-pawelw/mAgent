import Foundation

public enum InlineMarkdownBoldToken: Equatable, Sendable {
    case text(String)
    case bold(String)
}

public enum InlineMarkdownBoldTokenizer {
    public static func tokenize(_ source: String) -> [InlineMarkdownBoldToken] {
        guard !source.isEmpty else { return [.text("")] }

        var tokens: [InlineMarkdownBoldToken] = []
        var buffer = ""

        func flushText() {
            guard !buffer.isEmpty else { return }
            tokens.append(.text(buffer))
            buffer.removeAll(keepingCapacity: true)
        }

        var index = source.startIndex
        while index < source.endIndex {
            guard let openRange = source[index...].range(of: "**") else {
                buffer.append(contentsOf: source[index...])
                break
            }

            if openRange.lowerBound > index {
                buffer.append(contentsOf: source[index..<openRange.lowerBound])
            }

            let contentStart = openRange.upperBound
            guard let closeRange = source[contentStart...].range(of: "**"),
                  closeRange.lowerBound > contentStart else {
                buffer.append("**")
                index = contentStart
                continue
            }

            flushText()
            let boldText = String(source[contentStart..<closeRange.lowerBound])
            tokens.append(.bold(boldText))
            index = closeRange.upperBound
        }

        flushText()
        return tokens
    }
}
